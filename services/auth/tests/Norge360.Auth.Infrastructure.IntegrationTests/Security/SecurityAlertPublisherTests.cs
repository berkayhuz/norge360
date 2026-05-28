// <copyright file="SecurityAlertPublisherTests.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using FluentAssertions;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using Norge360.Auth.Application.Options;
using Norge360.Auth.Application.Records;
using Norge360.Auth.Infrastructure.Services;
using Norge360.Auth.TestKit.Logging;

namespace Norge360.Auth.Infrastructure.IntegrationTests.Security;

public sealed class SecurityAlertPublisherTests
{
    [Fact]
    public async Task PublishAsync_When_MetadataContainsSensitiveValues_Should_Redact_LogPayload()
    {
        var sensitiveValue = BuildSampleValue("refresh", "redaction");
        var bearerValue = BuildSampleValue("bearer", "redaction");
        var headerValue = BuildSampleValue("__Secure-Norge360-refresh=", "redaction");

        var sink = new TestLogSink();
        using var loggerFactory = LoggerFactory.Create(builder => builder.AddProvider(sink));
        var publisher = new SecurityAlertPublisher(
            loggerFactory.CreateLogger<SecurityAlertPublisher>(),
            Options.Create(new SecurityAlertOptions { EnableStructuredAlerts = true }));

        await publisher.PublishAsync(
            new SecurityAlert(
                "auth.refresh-reuse",
                "critical",
                $"Refresh replay detected. authorization=Bearer {bearerValue}",
                Guid.NewGuid(),
                Guid.NewGuid(),
                Guid.NewGuid(),
                "correlation-id",
                "trace-id",
                $"refreshToken={sensitiveValue};cookie={headerValue};path=/api/auth/refresh"),
            CancellationToken.None);

        var logPayload = string.Join(Environment.NewLine, sink.Entries.Select(entry => entry.Message));

        logPayload.Should().Contain("refreshToken=[redacted]");
        logPayload.Should().Contain("cookie=[redacted]");
        logPayload.Should().Contain("authorization=[redacted]");
        logPayload.Should().NotContain(sensitiveValue);
        logPayload.Should().NotContain(bearerValue);
        logPayload.Should().NotContain(headerValue);
    }

    private static string BuildSampleValue(string prefix, string suffix) =>
        string.Join("-", prefix, "sample", "value", suffix);
}
