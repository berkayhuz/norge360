// <copyright file="SecurityAlertPublisher.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using System.Text.Json;
using System.Text.RegularExpressions;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using Norge360.Auth.Application.Abstractions;
using Norge360.Auth.Application.Options;
using Norge360.Auth.Application.Records;

namespace Norge360.Auth.Infrastructure.Services;

public sealed partial class SecurityAlertPublisher(
    ILogger<SecurityAlertPublisher> logger,
    IOptions<SecurityAlertOptions> options) : ISecurityAlertPublisher
{
    public Task PublishAsync(SecurityAlert alert, CancellationToken cancellationToken)
    {
        if (!options.Value.EnableStructuredAlerts)
        {
            return Task.CompletedTask;
        }

        var sanitizedAlert = alert with
        {
            Message = RedactSensitiveLogValue(alert.Message) ?? string.Empty,
            Metadata = RedactSensitiveLogValue(alert.Metadata)
        };

        logger.LogWarning(
            "SECURITY_ALERT {Category} {Severity} Tenant={TenantId} User={UserId} Session={SessionId} CorrelationId={CorrelationId} TraceId={TraceId} Payload={Payload}",
            sanitizedAlert.Category,
            sanitizedAlert.Severity,
            sanitizedAlert.TenantId,
            sanitizedAlert.UserId,
            sanitizedAlert.SessionId,
            sanitizedAlert.CorrelationId,
            sanitizedAlert.TraceId,
            JsonSerializer.Serialize(sanitizedAlert));

        return Task.CompletedTask;
    }

    private static string? RedactSensitiveLogValue(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return value;
        }

        var redacted = SensitiveKeyValueRegex().Replace(
            value,
            match => $"{match.Groups["key"].Value}=[redacted]");

        return BearerTokenRegex().Replace(redacted, "Bearer [redacted]");
    }

    [GeneratedRegex(
        @"(?<key>(?i:password|passcode|token|jwt|cookie|authorization|secret|credential|recovery[-_ ]?code|mfa[-_ ]?code))\s*=\s*[^;,]+",
        RegexOptions.CultureInvariant)]
    private static partial Regex SensitiveKeyValueRegex();

    [GeneratedRegex(@"\bBearer\s+[A-Za-z0-9._~+/=-]+", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant)]
    private static partial Regex BearerTokenRegex();
}
