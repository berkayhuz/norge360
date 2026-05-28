// <copyright file="RequestContextSupport.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using System.Diagnostics;
using System.Diagnostics.Metrics;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Logging;

namespace Norge360.AspNetCore.RequestContext;

public static class RequestContextSupport
{
    public const string CorrelationIdHeaderName = "X-Correlation-Id";
    private const int MaxCorrelationIdLength = 128;
    private const int MaxLoggedHeaderLength = 512;

    public static string GetOrCreateCorrelationId(HttpContext context)
    {
        if (context.Items.TryGetValue(CorrelationIdHeaderName, out var value) &&
            value is string existing &&
            !string.IsNullOrWhiteSpace(existing))
        {
            return existing;
        }

        var correlationId = context.Request.Headers[CorrelationIdHeaderName].FirstOrDefault();
        correlationId = NormalizeCorrelationId(correlationId);
        correlationId ??= Activity.Current?.TraceId.ToString() ?? Guid.NewGuid().ToString("N");

        context.Items[CorrelationIdHeaderName] = correlationId;
        return correlationId;
    }

    public static IDisposable BeginScope(HttpContext context, ILogger logger)
    {
        var correlationId = GetOrCreateCorrelationId(context);
        context.Response.Headers[CorrelationIdHeaderName] = correlationId;

        return logger.BeginScope(new Dictionary<string, object?>
        {
            ["CorrelationId"] = correlationId,
            ["TraceId"] = GetTraceId(context),
            ["ClientIp"] = context.Connection.RemoteIpAddress?.ToString(),
            ["ProxyChain"] = SanitizeForLogScope(context.Request.Headers["X-Forwarded-For"].ToString())
        }) ?? NullScope.Instance;
    }

    public static string GetTraceId(HttpContext context) =>
        Activity.Current?.TraceId.ToString() ?? context.TraceIdentifier;

    public static void RecordCompletion(
        HttpContext context,
        ILogger logger,
        Histogram<double> requestDuration,
        string fallbackRoute,
        double elapsedMilliseconds,
        string serviceLabel)
    {
        var endpoint = context.GetEndpoint();
        var routeName = endpoint?.Metadata.GetMetadata<IRouteDiagnosticsMetadata>()?.Route ??
                        endpoint?.DisplayName ??
                        fallbackRoute;

        requestDuration.Record(
            elapsedMilliseconds,
            new KeyValuePair<string, object?>("method", context.Request.Method),
            new KeyValuePair<string, object?>("route", routeName),
            new KeyValuePair<string, object?>("status_code", context.Response.StatusCode),
            new KeyValuePair<string, object?>("service", serviceLabel));

        if (logger.IsEnabled(LogLevel.Information))
        {
            logger.LogInformation(
                "{Service} request {Method} {Path} responded {StatusCode} in {ElapsedMs:0.000} ms.",
                serviceLabel,
                context.Request.Method,
                context.Request.Path,
                context.Response.StatusCode,
                elapsedMilliseconds);
        }
    }

    private static string? NormalizeCorrelationId(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return null;
        }

        var trimmed = value.Trim();
        if (trimmed.Length > MaxCorrelationIdLength)
        {
            return null;
        }

        return trimmed.All(IsSafeCorrelationIdCharacter) ? trimmed : null;
    }

    private static bool IsSafeCorrelationIdCharacter(char value) =>
        char.IsAsciiLetterOrDigit(value) ||
        value is '-' or '_' or '.' or ':';

    private static string? SanitizeForLogScope(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return null;
        }

        var sanitized = value
            .Where(static c => !char.IsControl(c))
            .Take(MaxLoggedHeaderLength)
            .ToArray();

        return sanitized.Length == 0 ? null : new string(sanitized);
    }
}
