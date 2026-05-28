// <copyright file="DomainEntitiesBenchmarks.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using BenchmarkDotNet.Attributes;
using Norge360.Auth.Domain.Entities;

namespace Norge360.Auth.Benchmarks;

[MemoryDiagnoser]
public class DomainEntitiesBenchmarks
{
    private User _user = default!;
    private UserSession _session = default!;
    private TenantInvitation _pendingInvitation = default!;
    private TenantInvitation _acceptedInvitation = default!;
    private TrustedDevice _trustedDevice = default!;
    private AuthVerificationToken _verificationToken = default!;
    private UserMfaRecoveryCode _recoveryCode = default!;

    [GlobalSetup]
    public void Setup()
    {
        _user = new User
        {
            Roles = "tenant-user,tenant-admin,tenant-user",
            Permissions = "customers.read,customers.write,customers.read"
        };

        _session = new UserSession
        {
            CreatedAt = DateTime.UtcNow.AddMinutes(-10),
            LastSeenAt = DateTime.UtcNow.AddMinutes(-2),
            RefreshTokenExpiresAt = DateTime.UtcNow.AddHours(1)
        };

        _pendingInvitation = new TenantInvitation
        {
            ExpiresAtUtc = DateTime.UtcNow.AddDays(2),
            IsDeleted = false
        };

        _acceptedInvitation = new TenantInvitation
        {
            ExpiresAtUtc = DateTime.UtcNow.AddDays(2),
            AcceptedAtUtc = DateTime.UtcNow
        };

        _trustedDevice = new TrustedDevice
        {
            TrustedAtUtc = DateTime.UtcNow.AddDays(-5),
            DeviceFingerprintHash = "hash"
        };

        _verificationToken = new AuthVerificationToken
        {
            ExpiresAtUtc = DateTime.UtcNow.AddMinutes(5),
            Purpose = "confirm-email",
            TokenHash = "hash"
        };

        _recoveryCode = new UserMfaRecoveryCode
        {
            CodeHash = "hash"
        };
    }

    [Benchmark] public object User_GetRoles() => _user.GetRoles();
    [Benchmark] public object User_GetPermissions() => _user.GetPermissions();

    [Benchmark] public bool UserSession_IsRevoked() => _session.IsRevoked;
    [Benchmark] public void UserSession_Revoke() => _session.Revoke(DateTime.UtcNow, "manual_revoke");
    [Benchmark] public void UserSession_MarkRefreshRotated() => _session.MarkRefreshRotated(DateTime.UtcNow);
    [Benchmark] public void UserSession_MarkRefreshTokenReuse() => _session.MarkRefreshTokenReuse(DateTime.UtcNow, "reuse_detected");

    [Benchmark] public bool TenantInvitation_IsPending() => _pendingInvitation.IsPending(DateTime.UtcNow);
    [Benchmark] public string TenantInvitation_GetStatus_Pending() => _pendingInvitation.GetStatus(DateTime.UtcNow);
    [Benchmark] public string TenantInvitation_GetStatus_Accepted() => _acceptedInvitation.GetStatus(DateTime.UtcNow);

    [Benchmark] public bool TrustedDevice_IsRevoked() => _trustedDevice.IsRevoked;
    [Benchmark] public void TrustedDevice_MarkSeen() => _trustedDevice.MarkSeen(DateTime.UtcNow, "10.10.0.10", "bench-agent");
    [Benchmark] public void TrustedDevice_Revoke() => _trustedDevice.Revoke(DateTime.UtcNow, "manual");

    [Benchmark] public bool AuthVerificationToken_IsConsumed() => _verificationToken.IsConsumed;
    [Benchmark] public bool AuthVerificationToken_IsExpired() => _verificationToken.IsExpired(DateTime.UtcNow);
    [Benchmark] public void AuthVerificationToken_Consume() => _verificationToken.Consume(DateTime.UtcNow, "10.10.0.10");

    [Benchmark] public bool UserMfaRecoveryCode_IsConsumed() => _recoveryCode.IsConsumed;
    [Benchmark] public void UserMfaRecoveryCode_Consume() => _recoveryCode.Consume(DateTime.UtcNow, "10.10.0.10");
}
