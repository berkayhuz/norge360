// <copyright file="InfrastructureSecurityServicesBenchmarks.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using BenchmarkDotNet.Attributes;
using Microsoft.Extensions.Options;
using Norge360.Auth.Application.Options;
using Norge360.Auth.Infrastructure.Services;
using Norge360.Clock;

namespace Norge360.Auth.Benchmarks;

[MemoryDiagnoser]
public class InfrastructureSecurityServicesBenchmarks
{
    private RefreshTokenService _refreshTokenService = default!;
    private RecoveryCodeService _recoveryCodeService = default!;
    private AuthVerificationTokenService _verificationTokenService = default!;
    private AuthenticatorTotpService _totpService = default!;
    private string _refreshToken = string.Empty;
    private string _refreshTokenHash = string.Empty;
    private string _totpSharedKey = string.Empty;
    private string _totpValidCode = string.Empty;
    private Guid _tenantId;
    private Guid _userId;

    [GlobalSetup]
    public void Setup()
    {
        _tenantId = Guid.NewGuid();
        _userId = Guid.NewGuid();

        _refreshTokenService = new RefreshTokenService(
            Options.Create(new JwtOptions
            {
                RefreshTokenHours = 8,
                RefreshTokenPersistentDays = 14
            }),
            new FixedClock(DateTimeOffset.UtcNow));

        _recoveryCodeService = new RecoveryCodeService();
        _verificationTokenService = new AuthVerificationTokenService(Options.Create(new AccountLifecycleOptions
        {
            TokenBytes = 48
        }));
        _totpService = new AuthenticatorTotpService();

        var generatedRefresh = _refreshTokenService.Generate(isPersistent: true);
        _refreshToken = generatedRefresh.Token;
        _refreshTokenHash = generatedRefresh.Hash;

        _totpSharedKey = _totpService.GenerateSharedKey();
        // A syntactically valid 6-digit code; benchmark covers method execution path.
        _totpValidCode = "123456";
    }

    [Benchmark] public object RefreshToken_Generate_Persistent() => _refreshTokenService.Generate(isPersistent: true);
    [Benchmark] public object RefreshToken_Generate_NonPersistent() => _refreshTokenService.Generate(isPersistent: false);
    [Benchmark] public bool RefreshToken_Verify_Valid() => _refreshTokenService.Verify(_refreshToken, _refreshTokenHash);
    [Benchmark] public bool RefreshToken_Verify_Invalid() => _refreshTokenService.Verify("invalid-token", _refreshTokenHash);

    [Benchmark] public object RecoveryCode_Generate_10Codes() => _recoveryCodeService.GenerateCodes(10);
    [Benchmark] public string RecoveryCode_Hash() => _recoveryCodeService.HashCode(_tenantId, _userId, "ABCD1-EFGH2");

    [Benchmark] public string VerificationToken_Generate() => _verificationTokenService.GenerateToken();
    [Benchmark] public string VerificationToken_Hash() => _verificationTokenService.HashToken("verification-token");

    [Benchmark] public string Totp_GenerateSharedKey() => _totpService.GenerateSharedKey();
    [Benchmark] public string Totp_BuildUri() => _totpService.BuildAuthenticatorUri("Norge360", "tester@example.test", _totpSharedKey);
    [Benchmark] public bool Totp_VerifyCode() => _totpService.VerifyCode(_totpSharedKey, _totpValidCode, DateTime.UtcNow);

    private sealed class FixedClock(DateTimeOffset now) : IClock
    {
        public DateTimeOffset UtcNow { get; } = now;

        public DateTime UtcDateTime { get; } = now.UtcDateTime;
    }
}

