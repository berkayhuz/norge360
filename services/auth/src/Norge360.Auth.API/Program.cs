// <copyright file="Program.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using System.Security.Cryptography;
using System.Text;
using System.Threading.RateLimiting;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.Extensions.Options;
using Microsoft.OpenApi;
using Norge360.AspNetCore.Health;
using Norge360.AspNetCore.Localization.DependencyInjection;
using Norge360.AspNetCore.ProblemDetails;
using Norge360.AspNetCore.RequestContext;
using Norge360.AspNetCore.TrustedGateway.Options;
using Norge360.Auth.API.Accessors;
using Norge360.Auth.API.Configurations;
using Norge360.Auth.API.Cookies;
using Norge360.Auth.API.Exceptions;
using Norge360.Auth.API.Health;
using Norge360.Auth.API.Middlewares;
using Norge360.Auth.API.Security;
using Norge360.Auth.Application.Abstractions;
using Norge360.Auth.Application.DependencyInjection;
using Norge360.Auth.Application.Diagnostics;
using Norge360.Auth.Application.Options;
using Norge360.Auth.Infrastructure.DependencyInjection;
using Norge360.Configuration.AwsParameterStore;
using OpenTelemetry.Metrics;
using OpenTelemetry.Resources;
using OpenTelemetry.Trace;

var builder = WebApplication.CreateBuilder(args);
builder.Configuration.AddNorge360AwsParameterStore(builder.Environment);

builder.Logging.ClearProviders();
builder.Logging.AddConsole();
builder.Logging.AddDebug();

builder.Services.AddNorge360ProblemDetails();
builder.Services.AddNorge360Localization();
builder.Services.AddExceptionHandler<GlobalExceptionHandler>();

builder.Services
    .AddOptions<ApiCorsOptions>()
    .BindConfiguration(ApiCorsOptions.SectionName)
    .ValidateDataAnnotations()
    .ValidateOnStart();

builder.Services
    .AddOptions<ApiForwardedHeadersOptions>()
    .BindConfiguration(ApiForwardedHeadersOptions.SectionName)
    .ValidateDataAnnotations()
    .ValidateOnStart();

builder.Services
    .AddOptions<ApiSecurityHeadersOptions>()
    .BindConfiguration(ApiSecurityHeadersOptions.SectionName)
    .ValidateDataAnnotations()
    .ValidateOnStart();

builder.Services
    .AddOptions<TenantResolutionOptions>()
    .BindConfiguration(TenantResolutionOptions.SectionName)
    .ValidateOnStart();

builder.Services
    .AddOptions<TokenTransportOptions>()
    .BindConfiguration(TokenTransportOptions.SectionName)
    .ValidateOnStart();

builder.Services
    .AddOptions<TrustedGatewayOptions>()
    .BindConfiguration(TrustedGatewayOptions.SectionName)
    .ValidateOnStart();

builder.Services
    .AddOptions<InternalIdentityOptions>()
    .BindConfiguration(InternalIdentityOptions.SectionName)
    .Validate(options => options.AllowedSources.Length > 0, "Security:InternalIdentity:AllowedSources must contain at least one source.")
    .ValidateOnStart();

builder.Services
    .AddOptions<AuthRateLimitingOptions>()
    .BindConfiguration(AuthRateLimitingOptions.SectionName)
    .ValidateOnStart();

builder.Services.AddSingleton<IValidateOptions<ApiCorsOptions>, ApiCorsOptionsValidation>();
builder.Services.AddSingleton<IValidateOptions<ApiForwardedHeadersOptions>, ApiForwardedHeadersOptionsValidation>();
builder.Services.AddSingleton<IValidateOptions<ApiSecurityHeadersOptions>, ApiSecurityHeadersOptionsValidation>();
builder.Services.AddSingleton<IValidateOptions<TenantResolutionOptions>, TenantResolutionOptionsValidation>();
builder.Services.AddSingleton<IValidateOptions<TokenTransportOptions>, TokenTransportOptionsValidation>();
builder.Services.AddSingleton<IValidateOptions<TrustedGatewayOptions>, AuthTrustedGatewayOptionsValidation>();
builder.Services.AddSingleton<IValidateOptions<AuthRateLimitingOptions>, AuthRateLimitingOptionsValidation>();

builder.Services.AddSingleton<IConfigureOptions<ForwardedHeadersOptions>, ConfigureApiForwardedHeaders>();
builder.Services.AddSingleton<AuthCookieService>();
builder.Services.AddScoped<AuthRequestContextAccessor>();
builder.Services.AddScoped<ITenantContextAccessor, HttpTenantContextAccessor>();
builder.Services.AddHttpContextAccessor();
builder.Services.AddControllers();
builder.Services.AddEndpointsApiExplorer();
AddOpenTelemetry(builder.Services, builder.Configuration, "Norge360.Auth.API", "Norge360.Auth", "Norge360.Auth.API.Requests");

builder.Services.AddSwaggerGen(options =>
{
    options.SwaggerDoc("v1", new OpenApiInfo
    {
        Title = builder.Configuration["OpenApi:Title"] ?? "Norge360 Auth API",
        Version = builder.Configuration["OpenApi:Version"] ?? "v1"
    });

    options.AddSecurityDefinition(JwtBearerDefaults.AuthenticationScheme, new OpenApiSecurityScheme
    {
        In = ParameterLocation.Header,
        Name = "Authorization",
        Type = SecuritySchemeType.Http,
        Scheme = "bearer",
        BearerFormat = "JWT",
        Description = "Bearer access token."
    });
});

var corsOptions = builder.Configuration.GetSection(ApiCorsOptions.SectionName).Get<ApiCorsOptions>()
    ?? throw new InvalidOperationException("Security:Cors configuration is missing.");

builder.Services.AddCors(options =>
{
    options.AddPolicy(ApiCorsOptions.PolicyName, policy =>
    {
        policy.WithOrigins(corsOptions.AllowedOrigins)
            .AllowAnyHeader()
            .AllowAnyMethod();

        if (corsOptions.AllowCredentials)
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
        var tenant = context.HttpContext.Request.Headers["X-Tenant-Id"].FirstOrDefault()
            ?? context.HttpContext.Request.Headers["X-Tenant-Slug"].FirstOrDefault();
        var tenantHash = HashForTag(tenant);
        var environment = builder.Environment.EnvironmentName.ToLowerInvariant();

        AuthMetrics.RateLimitRejected.Add(
            1,
            new KeyValuePair<string, object?>("endpoint", path),
            new KeyValuePair<string, object?>("policy", "auth-global"),
            new KeyValuePair<string, object?>("reason", "rejected"),
            new KeyValuePair<string, object?>("tenant_hash", tenantHash),
            new KeyValuePair<string, object?>("environment", environment));

        await context.HttpContext.RequestServices.GetRequiredService<ISecurityAlertPublisher>().PublishAsync(
            new Norge360.Auth.Application.Records.SecurityAlert(
                "auth.rate-limit.rejected",
                "warning",
                "Authentication rate limit rejected request.",
                Guid.Empty,
                null,
                null,
                correlationId,
                context.HttpContext.TraceIdentifier,
                $"path={path};method={context.HttpContext.Request.Method}"),
            cancellationToken);

        await ProblemDetailsSupport.WriteProblemAsync(
            context.HttpContext,
            StatusCodes.Status429TooManyRequests,
            "Rate limit exceeded",
            "Too many authentication requests were sent.",
            errorCode: "auth_rate_limit_exceeded",
            cancellationToken: cancellationToken);
    };

    options.GlobalLimiter = PartitionedRateLimiter.Create<HttpContext, string>(httpContext =>
        RateLimitPartition.GetFixedWindowLimiter(
            partitionKey: $"global:{httpContext.Connection.RemoteIpAddress?.ToString() ?? "unknown"}",
            factory: _ => GetAuthRateLimitingOptions(httpContext).Global.ToLimiterOptions()));

    options.AddPolicy(AuthRateLimitingOptions.LoginPolicyName, httpContext =>
        RateLimitPartition.GetFixedWindowLimiter(
            partitionKey: BuildAuthRateLimitPartitionKey(httpContext, "login"),
            factory: _ => GetAuthRateLimitingOptions(httpContext).Login.ToLimiterOptions()));

    options.AddPolicy(AuthRateLimitingOptions.RegisterPolicyName, httpContext =>
        RateLimitPartition.GetFixedWindowLimiter(
            partitionKey: BuildAuthRateLimitPartitionKey(httpContext, "register"),
            factory: _ => GetAuthRateLimitingOptions(httpContext).Register.ToLimiterOptions()));

    options.AddPolicy(AuthRateLimitingOptions.RefreshPolicyName, httpContext =>
        RateLimitPartition.GetFixedWindowLimiter(
            partitionKey: BuildAuthRateLimitPartitionKey(httpContext, "refresh"),
            factory: _ => GetAuthRateLimitingOptions(httpContext).Refresh.ToLimiterOptions()));

    options.AddPolicy(AuthRateLimitingOptions.LogoutPolicyName, httpContext =>
        RateLimitPartition.GetFixedWindowLimiter(
            partitionKey: BuildAuthRateLimitPartitionKey(httpContext, "logout"),
            factory: _ => GetAuthRateLimitingOptions(httpContext).Logout.ToLimiterOptions()));

    options.AddPolicy(AuthRateLimitingOptions.InvitePolicyName, httpContext =>
        RateLimitPartition.GetFixedWindowLimiter(
            partitionKey: BuildAuthRateLimitPartitionKey(httpContext, "invite"),
            factory: _ => GetAuthRateLimitingOptions(httpContext).Invite.ToLimiterOptions()));

    options.AddPolicy(AuthRateLimitingOptions.RoleManagementPolicyName, httpContext =>
        RateLimitPartition.GetFixedWindowLimiter(
            partitionKey: BuildAuthRateLimitPartitionKey(httpContext, "roles"),
            factory: _ => GetAuthRateLimitingOptions(httpContext).RoleManagement.ToLimiterOptions()));

    options.AddPolicy(AuthRateLimitingOptions.PasswordRecoveryPolicyName, httpContext =>
        RateLimitPartition.GetFixedWindowLimiter(
            partitionKey: BuildAuthRateLimitPartitionKey(httpContext, "password-recovery"),
            factory: _ => GetAuthRateLimitingOptions(httpContext).PasswordRecovery.ToLimiterOptions()));

    options.AddPolicy(AuthRateLimitingOptions.EmailConfirmationPolicyName, httpContext =>
        RateLimitPartition.GetFixedWindowLimiter(
            partitionKey: BuildAuthRateLimitPartitionKey(httpContext, "email-confirmation"),
            factory: _ => GetAuthRateLimitingOptions(httpContext).EmailConfirmation.ToLimiterOptions()));
});

var authorizationOptions = builder.Configuration.GetSection(AuthorizationOptions.SectionName).Get<AuthorizationOptions>() ?? new AuthorizationOptions();
builder.Services.AddNorge360Authorization(authorizationOptions);

builder.Services.AddHealthChecks()
    .AddCheck<AuthDatabaseConnectivityHealthCheck>("identity-db-connectivity", tags: ["ready", "startup"])
    .AddCheck<AuthDatabaseQueryHealthCheck>("identity-db-query", tags: ["ready"])
    .AddCheck<AuthPendingMigrationsHealthCheck>("identity-db-migrations", tags: ["ready", "startup"])
    .AddCheck<DistributedCacheAvailabilityHealthCheck>("distributed-cache", tags: ["ready", "startup"])
    .AddCheck<JwtSigningKeyHealthCheck>("jwt-signing-keys", tags: ["ready", "startup"])
    .AddCheck<TrustedGatewayConfigurationHealthCheck>("trusted-gateway-config", tags: ["ready", "startup"]);

builder.Services.AddAuthApplication();
builder.Services.AddAuthInfrastructure(builder.Configuration);

var app = builder.Build();

app.UseMiddleware<RequestContextMiddleware>();
app.UseExceptionHandler();
app.UseMiddleware<AuthRequestBodySizeLimitMiddleware>();
app.UseMiddleware<TrustedGatewayMiddleware>();
app.UseForwardedHeaders();
if (ShouldUseHttpsRedirection(app))
{
    app.UseHttpsRedirection();
}
app.UseMiddleware<TenantResolutionMiddleware>();
app.UseMiddleware<CookieOriginProtectionMiddleware>();
app.UseMiddleware<SecurityHeadersMiddleware>();

if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

app.UseCors(ApiCorsOptions.PolicyName);
app.UseRateLimiter();
app.UseNorge360Localization();
app.UseAuthentication();
app.UseAuthorization();

app.MapControllers();

app.MapGet("/.well-known/jwks.json", (ITokenSigningKeyProvider signingKeyProvider, IOptions<JwtOptions> jwtOptions) =>
        Results.Ok(signingKeyProvider.GetJwksDocument(jwtOptions.Value.Issuer)))
    .AllowAnonymous()
    .WithMetadata(new RouteDiagnosticsMetadata("/.well-known/jwks.json"));

app.MapGet("/.well-known/openid-configuration", (HttpContext httpContext, IOptions<JwtOptions> jwtOptions) =>
{
    var issuer = jwtOptions.Value.Issuer.TrimEnd('/');
    var forwardedPrefix = httpContext.Request.Headers["X-Forwarded-Prefix"].FirstOrDefault()?.TrimEnd('/');
    var jwksUri = string.IsNullOrWhiteSpace(forwardedPrefix)
        ? $"{issuer}/.well-known/jwks.json"
        : $"{issuer}{forwardedPrefix}/.well-known/jwks.json";

    return Results.Ok(new
    {
        issuer,
        jwks_uri = jwksUri,
        token_endpoint = $"{issuer}/api/auth/login",
        response_types_supported = new[] { "token" },
        subject_types_supported = new[] { "public" },
        id_token_signing_alg_values_supported = new[] { "RS256" },
        token_endpoint_auth_methods_supported = new[] { "none" },
        claims_supported = new[] { "sub", "sid", "tenant_id", "role", "permission", "token_version" }
    });
})
    .AllowAnonymous()
    .WithMetadata(new RouteDiagnosticsMetadata("/.well-known/openid-configuration"));

app.MapHealthChecks("/health/live", HealthResponseWriter.CreateMinimalOptions(registration => registration.Tags.Contains("live")))
   .AllowAnonymous()
   .WithMetadata(new RouteDiagnosticsMetadata("/health/live"));

app.MapHealthChecks("/health/ready", HealthResponseWriter.CreateMinimalOptions(registration => registration.Tags.Contains("ready")))
   .AllowAnonymous()
   .WithMetadata(new RouteDiagnosticsMetadata("/health/ready"));

app.MapHealthChecks("/health/startup", HealthResponseWriter.CreateMinimalOptions(registration => registration.Tags.Contains("startup")))
   .AllowAnonymous()
   .WithMetadata(new RouteDiagnosticsMetadata("/health/startup"));

var skipInfrastructureInitialization = app.Configuration.GetValue<bool>("Testing:SkipInfrastructureInitialization");
if (!skipInfrastructureInitialization)
{
    await app.Services.InitializeAuthInfrastructureAsync(CancellationToken.None);
}

await app.RunAsync();

static void AddOpenTelemetry(IServiceCollection services, IConfiguration configuration, string serviceName, params string[] meterNames)
{
    var otlpEndpoint = configuration["OpenTelemetry:Otlp:Endpoint"] ?? configuration["OTEL_EXPORTER_OTLP_ENDPOINT"];
    var telemetry = services.AddOpenTelemetry()
        .ConfigureResource(resource => resource.AddService(serviceName));

    telemetry.WithTracing(tracing =>
    {
        tracing.AddAspNetCoreInstrumentation(options => options.RecordException = true);
        tracing.AddHttpClientInstrumentation(options => options.RecordException = true);
        tracing.AddEntityFrameworkCoreInstrumentation();

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

static string BuildAuthRateLimitPartitionKey(HttpContext httpContext, string policy)
{
    var ip = httpContext.Connection.RemoteIpAddress?.ToString() ?? "unknown";
    var tenant = httpContext.User.FindFirst("tenant_id")?.Value;

    if (string.IsNullOrWhiteSpace(tenant) && TrustedGatewayMiddleware.IsTrustedGatewayRequest(httpContext))
    {
        tenant =
            httpContext.Request.Headers["X-Tenant-Id"].FirstOrDefault() ??
            httpContext.Request.Headers["X-Tenant-Slug"].FirstOrDefault();
    }

    tenant ??= "anonymous";

    return $"{policy}:{ip}:{tenant}:{httpContext.Request.Path.Value?.ToLowerInvariant()}";
}

static AuthRateLimitingOptions GetAuthRateLimitingOptions(HttpContext httpContext) =>
    httpContext.RequestServices.GetRequiredService<IOptions<AuthRateLimitingOptions>>().Value;

static string HashForTag(string? value)
{
    if (string.IsNullOrWhiteSpace(value))
    {
        return "anonymous";
    }

    var bytes = SHA256.HashData(Encoding.UTF8.GetBytes(value));
    return Convert.ToHexString(bytes[..6]).ToLowerInvariant();
}

public partial class Program;
