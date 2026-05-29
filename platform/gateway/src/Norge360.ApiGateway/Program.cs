// <copyright file="Program.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using System.Threading.RateLimiting;
using Microsoft.AspNetCore.Http.Features;
using Microsoft.Extensions.Diagnostics.HealthChecks;
using Microsoft.Extensions.Options;
using Norge360.ApiGateway.Diagnostics;
using Norge360.ApiGateway.Exceptions;
using Norge360.ApiGateway.Health;
using Norge360.ApiGateway.Middlewares;
using Norge360.ApiGateway.Options;
using Norge360.ApiGateway.Security;
using Norge360.AspNetCore.Health;
using Norge360.AspNetCore.ProblemDetails;
using Norge360.AspNetCore.RequestContext;
using Norge360.AspNetCore.TrustedGateway.Abstractions;
using Norge360.AspNetCore.TrustedGateway.Options;
using Norge360.AspNetCore.TrustedGateway.Signing;
using OpenTelemetry.Metrics;
using OpenTelemetry.Resources;
using OpenTelemetry.Trace;
using Yarp.ReverseProxy.Transforms;

const string FrontendCorsPolicyName = "frontend-cors";
const string ProxyRateLimitPolicyName = "gateway-proxy";
const string TrustedGatewaySigningMetadataKey = "TrustedGatewaySigning";
const long AuthProxyBodyLimitBytes = 16 * 1024;

var builder = WebApplication.CreateBuilder(args);

builder.Logging.ClearProviders();
builder.Logging.AddConsole();
builder.Logging.AddDebug();

builder.Services.AddNorge360ProblemDetails();
builder.Services.AddExceptionHandler<GatewayExceptionHandler>();

builder.Services.AddSingleton<IValidateOptions<GatewayCorsOptions>, GatewayCorsOptionsValidation>();
builder.Services.AddSingleton<IValidateOptions<GatewayForwardedHeadersOptions>, GatewayForwardedHeadersOptionsValidation>();
builder.Services.AddSingleton<IValidateOptions<GatewaySecurityHeadersOptions>, GatewaySecurityHeadersOptionsValidation>();
builder.Services.AddSingleton<IValidateOptions<GatewayRateLimitingOptions>, GatewayRateLimitingOptionsValidation>();
builder.Services.AddSingleton<IValidateOptions<TrustedGatewayOptions>, GatewayTrustedCallerOptionsValidation>();

builder.Services
    .AddOptions<GatewayCorsOptions>()
    .BindConfiguration(GatewayCorsOptions.SectionName)
    .ValidateOnStart();

builder.Services
    .AddOptions<GatewayForwardedHeadersOptions>()
    .BindConfiguration(GatewayForwardedHeadersOptions.SectionName)
    .ValidateOnStart();

builder.Services
    .AddOptions<GatewaySecurityHeadersOptions>()
    .BindConfiguration(GatewaySecurityHeadersOptions.SectionName)
    .ValidateOnStart();

builder.Services
    .AddOptions<GatewayRateLimitingOptions>()
    .BindConfiguration(GatewayRateLimitingOptions.SectionName)
    .ValidateOnStart();

builder.Services
    .AddOptions<TrustedGatewayOptions>()
    .BindConfiguration(GatewayTrustedCallerOptions.SectionName)
    .ValidateOnStart();

builder.Services.AddSingleton<IConfigureOptions<ForwardedHeadersOptions>, ConfigureGatewayForwardedHeaders>();

builder.Services.AddSingleton<ITrustedGatewaySigner>(serviceProvider =>
    new TrustedGatewaySigner(serviceProvider.GetRequiredService<IOptions<TrustedGatewayOptions>>().Value));

builder.Services.AddScoped<GatewayTrustedRequestTransform>();
AddOpenTelemetry(builder.Services, builder.Configuration, "Norge360.ApiGateway", "Norge360.ApiGateway", "Norge360.ApiGateway.Requests");

var gatewayCorsOptions = builder.Configuration.GetSection(GatewayCorsOptions.SectionName).Get<GatewayCorsOptions>()
    ?? throw new InvalidOperationException("Gateway CORS configuration is missing.");

var gatewayRateLimitingOptions = builder.Configuration.GetSection(GatewayRateLimitingOptions.SectionName).Get<GatewayRateLimitingOptions>()
    ?? throw new InvalidOperationException("Gateway rate limiting configuration is missing.");

var trustedGatewayOptions = builder.Configuration
    .GetSection(GatewayTrustedCallerOptions.SectionName)
    .Get<TrustedGatewayOptions>()
    ?? throw new InvalidOperationException("Security:TrustedGateway configuration is missing.");

ValidateReverseProxyDestinations(builder.Configuration, builder.Environment);

if (!trustedGatewayOptions.Keys.Any(x =>
        x.Enabled &&
        x.SignRequests &&
        string.Equals(x.KeyId, trustedGatewayOptions.CurrentKeyId, StringComparison.Ordinal) &&
        !string.IsNullOrWhiteSpace(x.Secret)))
{
    throw new InvalidOperationException("Security:TrustedGateway current signing key is missing.");
}

builder.Services.AddCors(options =>
{
    options.AddPolicy(FrontendCorsPolicyName, policy =>
    {
        policy
            .WithOrigins(gatewayCorsOptions.AllowedOrigins)
            .AllowAnyHeader()
            .AllowAnyMethod();

        if (gatewayCorsOptions.AllowCredentials)
        {
            policy.AllowCredentials();
        }
    });
});

builder.Services.AddRateLimiter(options =>
{
    options.RejectionStatusCode = StatusCodes.Status429TooManyRequests;

    options.OnRejected = async (context, cancellationToken) =>
    {
        var correlationId = RequestContextSupport.GetOrCreateCorrelationId(context.HttpContext);
        var path = context.HttpContext.Request.Path.Value;
        var environment = builder.Environment.EnvironmentName.ToLowerInvariant();

        GatewayMetrics.RateLimitRejected.Add(
            1,
            new KeyValuePair<string, object?>("endpoint", path),
            new KeyValuePair<string, object?>("policy", ProxyRateLimitPolicyName),
            new KeyValuePair<string, object?>("reason", "rejected"),
            new KeyValuePair<string, object?>("environment", environment));

        context.HttpContext.RequestServices
            .GetRequiredService<ILoggerFactory>()
            .CreateLogger("Norge360.ApiGateway.SecurityAlerts")
            .LogWarning(
                "SECURITY_ALERT {Category} {Severity} CorrelationId={CorrelationId} TraceId={TraceId} Payload={Payload}",
                "gateway.rate-limit.rejected",
                "warning",
                correlationId,
                context.HttpContext.TraceIdentifier,
                $"path={path};method={context.HttpContext.Request.Method}");

        await ProblemDetailsSupport.WriteProblemAsync(
            context.HttpContext,
            StatusCodes.Status429TooManyRequests,
            "Rate limit exceeded",
            "Too many requests were sent to the gateway.",
            errorCode: "gateway_rate_limit_exceeded",
            cancellationToken: cancellationToken);
    };

    options.GlobalLimiter = PartitionedRateLimiter.Create<HttpContext, string>(httpContext =>
        RateLimitPartition.GetFixedWindowLimiter(
            partitionKey: httpContext.Connection.RemoteIpAddress?.ToString() ?? "unknown",
            factory: _ => gatewayRateLimitingOptions.Global.ToLimiterOptions()));

    options.AddPolicy(ProxyRateLimitPolicyName, httpContext =>
        RateLimitPartition.GetFixedWindowLimiter(
            partitionKey: $"proxy:{httpContext.Connection.RemoteIpAddress?.ToString() ?? "unknown"}",
            factory: _ => gatewayRateLimitingOptions.Proxy.ToLimiterOptions()));
});

builder.Services.AddHealthChecks()
    .AddCheck("self", () => HealthCheckResult.Healthy("Gateway process is running."), tags: ["live"])
    .AddCheck<GatewayReverseProxyConfigurationHealthCheck>("reverse-proxy-configuration", tags: ["ready", "startup"])
    .AddCheck<GatewaySigningConfigurationHealthCheck>("trusted-gateway-signing", tags: ["ready", "startup"]);

builder.Services
    .AddReverseProxy()
    .LoadFromConfig(builder.Configuration.GetSection("ReverseProxy"))
    .AddTransforms(transformBuilderContext =>
    {
        transformBuilderContext.AddRequestTransform(transformContext =>
        {
            var transform = transformContext.HttpContext.RequestServices.GetRequiredService<GatewayTrustedRequestTransform>();
            transform.ApplyCommonHeaders(transformContext);
            return ValueTask.CompletedTask;
        });

        transformBuilderContext.AddResponseTransform(transformContext =>
        {
            transformContext.HttpContext.Response.Headers[RequestContextSupport.CorrelationIdHeaderName] =
                RequestContextSupport.GetOrCreateCorrelationId(transformContext.HttpContext);

            return ValueTask.CompletedTask;
        });

        var metadata = transformBuilderContext.Route?.Metadata;
        if (metadata is not null &&
            metadata.TryGetValue(TrustedGatewaySigningMetadataKey, out var configured) &&
            bool.TryParse(configured, out var enabled) &&
            enabled)
        {
            transformBuilderContext.AddRequestTransform(async transformContext =>
            {
                var transform = transformContext.HttpContext.RequestServices.GetRequiredService<GatewayTrustedRequestTransform>();
                await transform.ApplySigningAsync(transformContext, transformContext.HttpContext.RequestAborted);
            });
        }
    });

var app = builder.Build();

app.UseMiddleware<RequestContextMiddleware>();
app.UseExceptionHandler();
app.UseForwardedHeaders();
if (ShouldUseHttpsRedirection(app))
{
    app.UseHttpsRedirection();
}
app.UseMiddleware<SecurityHeadersMiddleware>();
app.UseCors(FrontendCorsPolicyName);
app.UseRateLimiter();
app.Use(async (context, next) =>
{
    if (IsAuthWriteRequest(context.Request))
    {
        var maxBodySizeFeature = context.Features.Get<IHttpMaxRequestBodySizeFeature>();
        if (maxBodySizeFeature is not null && !maxBodySizeFeature.IsReadOnly)
        {
            maxBodySizeFeature.MaxRequestBodySize = AuthProxyBodyLimitBytes;
        }

        if (context.Request.ContentLength > AuthProxyBodyLimitBytes)
        {
            await ProblemDetailsSupport.WriteProblemAsync(
                context,
                StatusCodes.Status413PayloadTooLarge,
                "Request body too large",
                "Authentication request bodies are limited to 16 KB.",
                errorCode: "auth_body_too_large",
                cancellationToken: context.RequestAborted);

            return;
        }
    }

    await next();
});

app.MapHealthChecks(
        "/health/live",
        HealthResponseWriter.CreateMinimalOptions(registration => registration.Tags.Contains("live")))
    .WithMetadata(new RouteDiagnosticsMetadata("/health/live"));

app.MapHealthChecks(
        "/health/ready",
        HealthResponseWriter.CreateMinimalOptions(registration => registration.Tags.Contains("ready")))
    .WithMetadata(new RouteDiagnosticsMetadata("/health/ready"));

app.MapHealthChecks(
        "/health/startup",
        HealthResponseWriter.CreateMinimalOptions(registration => registration.Tags.Contains("startup")))
    .WithMetadata(new RouteDiagnosticsMetadata("/health/startup"));

app.MapReverseProxy(proxyPipeline =>
{
    proxyPipeline.Use(async (context, next) =>
    {
        context.Response.Headers["X-Proxy-Hop"] = "Norge360.ApiGateway";
        await next();
    });
})
    .RequireRateLimiting(ProxyRateLimitPolicyName)
    .WithMetadata(new RouteDiagnosticsMetadata("proxy"));

await app.RunAsync();

static bool IsAuthWriteRequest(HttpRequest request) =>
    HttpMethods.IsPost(request.Method) &&
    request.Path.StartsWithSegments("/api/auth", StringComparison.OrdinalIgnoreCase);

static void ValidateReverseProxyDestinations(IConfiguration configuration, IHostEnvironment environment)
{
    if (!environment.IsProduction())
    {
        return;
    }

    foreach (var cluster in configuration.GetSection("ReverseProxy:Clusters").GetChildren())
    {
        if (bool.TryParse(cluster.GetSection("HttpClient")["DangerousAcceptAnyServerCertificate"], out var acceptAnyCertificate) &&
            acceptAnyCertificate)
        {
            throw new InvalidOperationException($"ReverseProxy:Clusters:{cluster.Key}:HttpClient:DangerousAcceptAnyServerCertificate must be false in production.");
        }

        var destinations = cluster.GetSection("Destinations").GetChildren().ToArray();
        if (destinations.Length == 0)
        {
            throw new InvalidOperationException($"ReverseProxy:Clusters:{cluster.Key} must define at least one destination in production.");
        }

        foreach (var destination in destinations)
        {
            var address = destination["Address"];
            if (!Uri.TryCreate(address, UriKind.Absolute, out var uri) ||
                uri.Scheme is not ("http" or "https") ||
                uri.IsLoopback ||
                uri.Host.Contains("localhost", StringComparison.OrdinalIgnoreCase) ||
                uri.Host.Contains("127.0.0.1", StringComparison.OrdinalIgnoreCase) ||
                uri.Host.Contains("example", StringComparison.OrdinalIgnoreCase))
            {
                throw new InvalidOperationException($"ReverseProxy:Clusters:{cluster.Key}:Destinations:{destination.Key}:Address must be a production service URI.");
            }
        }
    }
}

static void AddOpenTelemetry(IServiceCollection services, IConfiguration configuration, string serviceName, params string[] meterNames)
{
    var otlpEndpoint = configuration["OpenTelemetry:Otlp:Endpoint"] ?? configuration["OTEL_EXPORTER_OTLP_ENDPOINT"];
    var telemetry = services.AddOpenTelemetry()
        .ConfigureResource(resource => resource.AddService(serviceName));

    telemetry.WithTracing(tracing =>
    {
        tracing.AddAspNetCoreInstrumentation(options => options.RecordException = true);
        tracing.AddHttpClientInstrumentation(options => options.RecordException = true);

        if (!string.IsNullOrWhiteSpace(otlpEndpoint))
        {
            tracing.AddOtlpExporter(options => options.Endpoint = new Uri(otlpEndpoint));
        }
    });

    telemetry.WithMetrics(metrics =>
    {
        metrics.AddAspNetCoreInstrumentation();
        metrics.AddHttpClientInstrumentation();
        metrics.AddMeter(meterNames);

        if (!string.IsNullOrWhiteSpace(otlpEndpoint))
        {
            metrics.AddOtlpExporter(options => options.Endpoint = new Uri(otlpEndpoint));
        }
    });
}

static bool ShouldUseHttpsRedirection(WebApplication app)
{
    if (app.Configuration.GetValue<bool>("LocalDevelopment:DisableHttpsRedirection"))
    {
        return false;
    }

    if (int.TryParse(app.Configuration["HTTPS_PORT"] ?? app.Configuration["ASPNETCORE_HTTPS_PORT"], out _))
    {
        return true;
    }

    return app.Configuration
        .GetSection("Kestrel:Endpoints")
        .GetChildren()
        .Any(endpoint => endpoint["Url"]?.StartsWith("https://", StringComparison.OrdinalIgnoreCase) == true);
}
