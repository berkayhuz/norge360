// <copyright file="HealthResponseWriter.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using System.Text.Json;
using Microsoft.AspNetCore.Diagnostics.HealthChecks;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Diagnostics.HealthChecks;
using Microsoft.Extensions.Hosting;
using Norge360.AspNetCore.RequestContext;

namespace Norge360.AspNetCore.Health;

public static class HealthResponseWriter
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web)
    {
        WriteIndented = false
    };

    public static Task WriteDetailedAsync(HttpContext context, HealthReport report)
    {
        context.Response.ContentType = "application/json";

        var payload = new
        {
            status = report.Status.ToString(),
            service = context.RequestServices.GetRequiredService<IHostEnvironment>().ApplicationName,
            durationMilliseconds = report.TotalDuration.TotalMilliseconds,
            traceId = context.TraceIdentifier,
            correlationId = RequestContextSupport.GetOrCreateCorrelationId(context),
            checks = report.Entries.Select(entry => new
            {
                name = entry.Key,
                status = entry.Value.Status.ToString(),
                tags = entry.Value.Tags.OrderBy(x => x, StringComparer.Ordinal).ToArray()
            })
        };

        return context.Response.WriteAsync(JsonSerializer.Serialize(payload, JsonOptions));
    }

    public static Task WriteMinimalAsync(HttpContext context, HealthReport report)
    {
        context.Response.ContentType = "application/json";

        var payload = new
        {
            status = report.Status.ToString()
        };

        return context.Response.WriteAsync(JsonSerializer.Serialize(payload, JsonOptions));
    }

    public static HealthCheckOptions CreateDetailedOptions(Func<HealthCheckRegistration, bool>? predicate = null) =>
        new()
        {
            Predicate = predicate,
            ResponseWriter = WriteDetailedAsync,
            ResultStatusCodes =
            {
                [HealthStatus.Healthy] = StatusCodes.Status200OK,
                [HealthStatus.Degraded] = StatusCodes.Status503ServiceUnavailable,
                [HealthStatus.Unhealthy] = StatusCodes.Status503ServiceUnavailable
            }
        };

    public static HealthCheckOptions CreateMinimalOptions(Func<HealthCheckRegistration, bool>? predicate = null) =>
        new()
        {
            Predicate = predicate,
            ResponseWriter = WriteMinimalAsync,
            ResultStatusCodes =
            {
                [HealthStatus.Healthy] = StatusCodes.Status200OK,
                [HealthStatus.Degraded] = StatusCodes.Status503ServiceUnavailable,
                [HealthStatus.Unhealthy] = StatusCodes.Status503ServiceUnavailable
            }
        };
}
