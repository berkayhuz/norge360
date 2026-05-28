// <copyright file="SecurityEntitiesTests.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using FluentAssertions;
using Norge360.Auth.Domain.Entities;

namespace Norge360.Auth.Domain.UnitTests.Entities;

public sealed class SecurityEntitiesTests
{
    [Fact]
    public void AuthVerificationToken_IsExpired_Should_Use_Upper_Boundary()
    {
        var expiresAt = new DateTime(2026, 1, 1, 10, 0, 0, DateTimeKind.Utc);
        var token = new AuthVerificationToken { ExpiresAtUtc = expiresAt };

        token.IsExpired(expiresAt.AddSeconds(-1)).Should().BeFalse();
        token.IsExpired(expiresAt).Should().BeTrue();
    }

    [Fact]
    public void AuthVerificationToken_Consume_Should_Set_Consumption_Metadata()
    {
        var utcNow = new DateTime(2026, 1, 2, 0, 0, 0, DateTimeKind.Utc);
        var token = new AuthVerificationToken();

        token.Consume(utcNow, "127.0.0.1");

        token.IsConsumed.Should().BeTrue();
        token.ConsumedAtUtc.Should().Be(utcNow);
        token.ConsumedByIpAddress.Should().Be("127.0.0.1");
    }

    [Fact]
    public void TenantInvitation_GetStatus_Should_Return_Expected_Values()
    {
        var now = new DateTime(2026, 2, 1, 0, 0, 0, DateTimeKind.Utc);
        var invitation = new TenantInvitation
        {
            ExpiresAtUtc = now.AddHours(1),
            IsDeleted = false
        };

        invitation.GetStatus(now).Should().Be("pending");

        invitation.AcceptedAtUtc = now;
        invitation.GetStatus(now).Should().Be("accepted");

        invitation.AcceptedAtUtc = null;
        invitation.RevokedAtUtc = now;
        invitation.GetStatus(now).Should().Be("revoked");

        invitation.RevokedAtUtc = null;
        invitation.ExpiresAtUtc = now.AddMinutes(-1);
        invitation.GetStatus(now).Should().Be("expired");
    }

    [Fact]
    public void UserSession_MarkRefreshTokenReuse_Should_Revoke_Session_And_Record_Reuse()
    {
        var session = new UserSession();
        var utcNow = new DateTime(2026, 1, 5, 12, 30, 0, DateTimeKind.Utc);

        session.MarkRefreshTokenReuse(utcNow, "reuse-detected");

        session.IsRevoked.Should().BeTrue();
        session.RefreshTokenReuseDetectedAt.Should().Be(utcNow);
        session.RevokedAt.Should().Be(utcNow);
        session.RevokedReason.Should().Be("reuse-detected");
    }

    [Fact]
    public void TrustedDevice_Revoke_Should_Be_Idempotent_For_Existing_Reason()
    {
        var firstTime = new DateTime(2026, 1, 1, 0, 0, 0, DateTimeKind.Utc);
        var secondTime = firstTime.AddHours(1);
        var device = new TrustedDevice();

        device.Revoke(firstTime, "first-reason");
        device.Revoke(secondTime, "second-reason");

        device.RevokedAtUtc.Should().Be(firstTime);
        device.RevokedReason.Should().Be("first-reason");
        device.UpdatedAt.Should().Be(secondTime);
    }

    [Fact]
    public void UserMfaRecoveryCode_Consume_Should_Set_Consumed_State_And_UpdatedAt()
    {
        var utcNow = new DateTime(2026, 1, 7, 9, 0, 0, DateTimeKind.Utc);
        var code = new UserMfaRecoveryCode();

        code.Consume(utcNow, "10.0.0.1");

        code.IsConsumed.Should().BeTrue();
        code.ConsumedAtUtc.Should().Be(utcNow);
        code.ConsumedByIpAddress.Should().Be("10.0.0.1");
        code.UpdatedAt.Should().Be(utcNow);
    }
}
