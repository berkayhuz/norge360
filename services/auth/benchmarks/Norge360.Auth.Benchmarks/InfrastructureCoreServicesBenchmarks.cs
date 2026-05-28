// <copyright file="InfrastructureCoreServicesBenchmarks.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using BenchmarkDotNet.Attributes;
using Microsoft.AspNetCore.DataProtection;
using Microsoft.Extensions.FileProviders;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Options;
using Norge360.Auth.Application.Options;
using Norge360.Auth.Domain.Entities;
using Norge360.Auth.Infrastructure.Services;
using Norge360.Clock;

namespace Norge360.Auth.Benchmarks;

[MemoryDiagnoser]
public class InfrastructureCoreServicesBenchmarks
{
    private TokenSigningKeyProvider _signingKeyProvider = default!;
    private OutboxPayloadProtector _outboxPayloadProtector = default!;
    private AuthenticatorKeyProtector _authenticatorKeyProtector = default!;
    private AuthSessionService _authSessionService = default!;
    private UserSession _activeSession = default!;
    private UserSession _expiredSession = default!;
    private string _protectedAuthenticatorKey = string.Empty;
    private string _protectedOutboxPayload = string.Empty;

    [GlobalSetup]
    public void Setup()
    {
        var dataProtectionProvider = DataProtectionProvider.Create(new DirectoryInfo(Path.Combine(Path.GetTempPath(), "norge360-bench-dp")));
        _outboxPayloadProtector = new OutboxPayloadProtector(dataProtectionProvider);
        _authenticatorKeyProtector = new AuthenticatorKeyProtector(dataProtectionProvider);

        _signingKeyProvider = new TokenSigningKeyProvider(
            Options.Create(new JwtOptions
            {
                Issuer = "https://auth.norge360.test",
                Audience = "norge360-api"
            }),
            new DevHostEnvironment());

        _authSessionService = new AuthSessionService(
            dbContext: null!,
            Options.Create(new SessionSecurityOptions
            {
                IdleTimeoutMinutes = 30,
                AbsoluteLifetimeDays = 7,
                MaxActiveSessions = 5
            }),
            new FixedClock(DateTimeOffset.UtcNow));

        _activeSession = new UserSession
        {
            CreatedAt = DateTime.UtcNow.AddMinutes(-5),
            LastSeenAt = DateTime.UtcNow.AddMinutes(-1),
            RefreshTokenExpiresAt = DateTime.UtcNow.AddHours(1)
        };
        _expiredSession = new UserSession
        {
            CreatedAt = DateTime.UtcNow.AddDays(-10),
            LastSeenAt = DateTime.UtcNow.AddHours(-2),
            RefreshTokenExpiresAt = DateTime.UtcNow.AddMinutes(-10)
        };

        _protectedAuthenticatorKey = _authenticatorKeyProtector.Protect("ABCDEFGHIJKLMNOPQRST");
        _protectedOutboxPayload = _outboxPayloadProtector.ProtectForStorage(
            eventName: "AuthPasswordResetRequestedV1",
            payload: "{\"email\":\"tester@example.test\"}");
    }

    [Benchmark] public object TokenSigning_GetCurrentSigningCredentials() => _signingKeyProvider.GetCurrentSigningCredentials();
    [Benchmark] public object TokenSigning_GetValidationKeys() => _signingKeyProvider.GetValidationKeys();
    [Benchmark] public object TokenSigning_GetJwksDocument() => _signingKeyProvider.GetJwksDocument("https://auth.norge360.test");

    [Benchmark] public string Outbox_Protect_Sensitive() => _outboxPayloadProtector.ProtectForStorage("notification.requested", "{\"x\":1}");
    [Benchmark] public string Outbox_Protect_NonSensitive() => _outboxPayloadProtector.ProtectForStorage("some.event", "{\"x\":1}");
    [Benchmark] public string Outbox_Unprotect() => _outboxPayloadProtector.UnprotectForPublish(_protectedOutboxPayload);

    [Benchmark] public string AuthenticatorKey_Protect() => _authenticatorKeyProtector.Protect("ABCDEFGHIJKLMNOPQRST");
    [Benchmark] public string AuthenticatorKey_Unprotect() => _authenticatorKeyProtector.Unprotect(_protectedAuthenticatorKey);

    [Benchmark] public bool AuthSession_IsExpired_Active() => _authSessionService.IsExpired(_activeSession, DateTime.UtcNow);
    [Benchmark] public bool AuthSession_IsExpired_Expired() => _authSessionService.IsExpired(_expiredSession, DateTime.UtcNow);

    private sealed class DevHostEnvironment : IHostEnvironment
    {
        public string EnvironmentName { get; set; } = Environments.Development;
        public string ApplicationName { get; set; } = "Norge360.Auth.Benchmarks";
        public string ContentRootPath { get; set; } = AppContext.BaseDirectory;
        public IFileProvider ContentRootFileProvider { get; set; } = new NullFileProvider();
    }

    private sealed class FixedClock(DateTimeOffset now) : IClock
    {
        public DateTimeOffset UtcNow { get; } = now;
        public DateTime UtcDateTime { get; } = now.UtcDateTime;
    }
}

