// <copyright file="AccountLifecycleCommandHandlersTests.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using System.Net;
using FluentAssertions;
using Microsoft.AspNetCore.Identity;
using Microsoft.Extensions.Options;
using Moq;
using Norge360.Auth.Application.Abstractions;
using Norge360.Auth.Application.Exceptions;
using Norge360.Auth.Application.Features.Commands;
using Norge360.Auth.Application.Features.Handlers;
using Norge360.Auth.Application.Options;
using Norge360.Auth.Contracts.IntegrationEvents;
using Norge360.Auth.Domain.Entities;
using Norge360.Auth.TestKit.Builders;
using Norge360.Auth.TestKit.Fakes;

namespace Norge360.Auth.Application.UnitTests.Handlers;

public sealed class AccountLifecycleCommandHandlersTests
{
    [Fact]
    public async Task ForgotPassword_Should_Be_Noop_For_Unknown_User()
    {
        var tenantId = Guid.NewGuid();
        var fixture = new LifecycleFixture(new FakeClock(new DateTime(2026, 1, 4, 0, 0, 0, DateTimeKind.Utc)));
        fixture.UserRepository.Setup(repository => repository.FindByTenantAndIdentityAsync(tenantId, "UNKNOWN@EXAMPLE.COM", It.IsAny<CancellationToken>()))
            .ReturnsAsync((User?)null);
        var sut = fixture.CreateForgotPasswordHandler();

        await sut.Handle(new ForgotPasswordCommand(tenantId, "unknown@example.com", null, null, null, null), CancellationToken.None);

        fixture.Outbox.Verify(outbox => outbox.AddAsync(
            It.IsAny<Guid>(),
            It.IsAny<string>(),
            It.IsAny<int>(),
            It.IsAny<string>(),
            It.IsAny<string>(),
            It.IsAny<AuthPasswordResetRequestedV1>(),
            It.IsAny<string>(),
            It.IsAny<string>(),
            It.IsAny<DateTime>(),
            It.IsAny<CancellationToken>()), Times.Never);
        fixture.AuthUnitOfWork.Verify(unitOfWork => unitOfWork.SaveChangesAsync(It.IsAny<CancellationToken>()), Times.Never);
    }

    [Fact]
    public async Task ForgotPassword_Should_Create_Reset_Token_And_Outbox_Message_For_Active_User()
    {
        var now = new DateTime(2026, 1, 4, 0, 0, 0, DateTimeKind.Utc);
        var tenantId = Guid.NewGuid();
        var user = AuthTestDataBuilder.User().WithTenant(tenantId).Build();
        user.EmailConfirmed = true;
        const string rawToken = "raw+token/with-slash";
        var encodedToken = Uri.EscapeDataString(rawToken);

        var fixture = new LifecycleFixture(new FakeClock(now));
        fixture.UserRepository.Setup(repository => repository.FindByTenantAndIdentityAsync(tenantId, user.NormalizedEmail, It.IsAny<CancellationToken>()))
            .ReturnsAsync(user);
        fixture.TokenService.Setup(service => service.GenerateToken()).Returns(rawToken);
        fixture.TokenService.Setup(service => service.HashToken(rawToken)).Returns("raw-token-hash");
        var sut = fixture.CreateForgotPasswordHandler();

        await sut.Handle(new ForgotPasswordCommand(tenantId, user.Email!, "127.0.0.1", "unit-test", "corr", "trace"), CancellationToken.None);

        fixture.TokenRepository.Verify(repository => repository.AddAsync(
            It.Is<AuthVerificationToken>(token =>
                token.TenantId == tenantId &&
                token.UserId == user.Id &&
                token.Purpose == AuthVerificationTokenPurpose.PasswordReset &&
                token.TokenHash == "raw-token-hash"),
            It.IsAny<CancellationToken>()), Times.Once);
        fixture.Outbox.Verify(outbox => outbox.AddAsync(
            It.IsAny<Guid>(),
            AuthPasswordResetRequestedV1.EventName,
            1,
            AuthPasswordResetRequestedV1.RoutingKey,
            "Norge360.Auth",
            It.Is<AuthPasswordResetRequestedV1>(evt =>
                evt.UserId == user.Id &&
                evt.TenantId == user.TenantId &&
                evt.Email == user.Email &&
                evt.Token == rawToken &&
                evt.ResetUrl.Contains($"tenantId={tenantId:D}", StringComparison.Ordinal) &&
                evt.ResetUrl.Contains($"userId={user.Id:D}", StringComparison.Ordinal) &&
                evt.ResetUrl.Contains($"token={encodedToken}", StringComparison.Ordinal)),
            "corr",
            "trace",
            now,
            It.IsAny<CancellationToken>()), Times.Once);
    }

    [Fact]
    public async Task ForgotPassword_Should_Not_Enqueue_Email_When_TargetCooldown_Is_Active()
    {
        var tenantId = Guid.NewGuid();
        var user = AuthTestDataBuilder.User().WithTenant(tenantId).Build();
        var fixture = new LifecycleFixture(new FakeClock(new DateTime(2026, 1, 4, 0, 0, 0, DateTimeKind.Utc)));
        fixture.UserRepository.Setup(repository => repository.FindByTenantAndIdentityAsync(tenantId, user.NormalizedEmail, It.IsAny<CancellationToken>()))
            .ReturnsAsync(user);
        fixture.CooldownStore.Setup(store => store.TryAcquireAsync("password-reset", tenantId, user.NormalizedEmail, It.IsAny<int>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(false);

        var sut = fixture.CreateForgotPasswordHandler();

        await sut.Handle(new ForgotPasswordCommand(tenantId, user.Email!, null, null, null, null), CancellationToken.None);

        fixture.TokenRepository.Verify(repository => repository.AddAsync(It.IsAny<AuthVerificationToken>(), It.IsAny<CancellationToken>()), Times.Never);
        fixture.Outbox.Verify(outbox => outbox.AddAsync(
            It.IsAny<Guid>(),
            It.IsAny<string>(),
            It.IsAny<int>(),
            It.IsAny<string>(),
            It.IsAny<string>(),
            It.IsAny<AuthPasswordResetRequestedV1>(),
            It.IsAny<string>(),
            It.IsAny<string>(),
            It.IsAny<DateTime>(),
            It.IsAny<CancellationToken>()), Times.Never);
        fixture.AuthUnitOfWork.Verify(unitOfWork => unitOfWork.SaveChangesAsync(It.IsAny<CancellationToken>()), Times.Never);
    }

    [Fact]
    public async Task ForgotPassword_Should_Use_Different_Cooldown_For_Different_Tenants()
    {
        var tenantA = Guid.NewGuid();
        var tenantB = Guid.NewGuid();
        var userA = AuthTestDataBuilder.User().WithTenant(tenantA).WithIdentity("usera", "same@example.com").Build();
        var userB = AuthTestDataBuilder.User().WithTenant(tenantB).WithIdentity("userb", "same@example.com").Build();
        var fixture = new LifecycleFixture(new FakeClock(new DateTime(2026, 1, 4, 0, 0, 0, DateTimeKind.Utc)));
        fixture.UserRepository.Setup(repository => repository.FindByTenantAndIdentityAsync(tenantA, "SAME@EXAMPLE.COM", It.IsAny<CancellationToken>()))
            .ReturnsAsync(userA);
        fixture.UserRepository.Setup(repository => repository.FindByTenantAndIdentityAsync(tenantB, "SAME@EXAMPLE.COM", It.IsAny<CancellationToken>()))
            .ReturnsAsync(userB);

        var sut = fixture.CreateForgotPasswordHandler();

        await sut.Handle(new ForgotPasswordCommand(tenantA, "same@example.com", null, null, null, null), CancellationToken.None);
        await sut.Handle(new ForgotPasswordCommand(tenantB, "same@example.com", null, null, null, null), CancellationToken.None);

        fixture.CooldownStore.Verify(store => store.TryAcquireAsync("password-reset", tenantA, "SAME@EXAMPLE.COM", It.IsAny<int>(), It.IsAny<CancellationToken>()), Times.Once);
        fixture.CooldownStore.Verify(store => store.TryAcquireAsync("password-reset", tenantB, "SAME@EXAMPLE.COM", It.IsAny<int>(), It.IsAny<CancellationToken>()), Times.Once);
    }

    [Fact]
    public async Task ForgotPassword_Should_Use_Different_Cooldown_For_Different_Emails()
    {
        var tenantId = Guid.NewGuid();
        var userA = AuthTestDataBuilder.User().WithTenant(tenantId).WithIdentity("usera", "alpha@example.com").Build();
        var userB = AuthTestDataBuilder.User().WithTenant(tenantId).WithIdentity("userb", "beta@example.com").Build();
        var fixture = new LifecycleFixture(new FakeClock(new DateTime(2026, 1, 4, 0, 0, 0, DateTimeKind.Utc)));
        fixture.UserRepository.Setup(repository => repository.FindByTenantAndIdentityAsync(tenantId, "ALPHA@EXAMPLE.COM", It.IsAny<CancellationToken>()))
            .ReturnsAsync(userA);
        fixture.UserRepository.Setup(repository => repository.FindByTenantAndIdentityAsync(tenantId, "BETA@EXAMPLE.COM", It.IsAny<CancellationToken>()))
            .ReturnsAsync(userB);

        var sut = fixture.CreateForgotPasswordHandler();

        await sut.Handle(new ForgotPasswordCommand(tenantId, "alpha@example.com", null, null, null, null), CancellationToken.None);
        await sut.Handle(new ForgotPasswordCommand(tenantId, "beta@example.com", null, null, null, null), CancellationToken.None);

        fixture.CooldownStore.Verify(store => store.TryAcquireAsync("password-reset", tenantId, "ALPHA@EXAMPLE.COM", It.IsAny<int>(), It.IsAny<CancellationToken>()), Times.Once);
        fixture.CooldownStore.Verify(store => store.TryAcquireAsync("password-reset", tenantId, "BETA@EXAMPLE.COM", It.IsAny<int>(), It.IsAny<CancellationToken>()), Times.Once);
    }

    [Fact]
    public async Task ForgotPassword_Should_Remain_Enumeration_Safe_When_Cooldown_Is_Active()
    {
        var tenantId = Guid.NewGuid();
        var existingUser = AuthTestDataBuilder.User().WithTenant(tenantId).WithIdentity("existing", "exists@example.com").Build();
        var fixture = new LifecycleFixture(new FakeClock(new DateTime(2026, 1, 4, 0, 0, 0, DateTimeKind.Utc)));
        fixture.UserRepository.Setup(repository => repository.FindByTenantAndIdentityAsync(tenantId, "EXISTS@EXAMPLE.COM", It.IsAny<CancellationToken>()))
            .ReturnsAsync(existingUser);
        fixture.UserRepository.Setup(repository => repository.FindByTenantAndIdentityAsync(tenantId, "MISSING@EXAMPLE.COM", It.IsAny<CancellationToken>()))
            .ReturnsAsync((User?)null);
        fixture.CooldownStore.Setup(store => store.TryAcquireAsync("password-reset", tenantId, "EXISTS@EXAMPLE.COM", It.IsAny<int>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(false);

        var sut = fixture.CreateForgotPasswordHandler();

        var existingAction = async () => await sut.Handle(new ForgotPasswordCommand(tenantId, "exists@example.com", null, null, null, null), CancellationToken.None);
        var missingAction = async () => await sut.Handle(new ForgotPasswordCommand(tenantId, "missing@example.com", null, null, null, null), CancellationToken.None);

        await existingAction.Should().NotThrowAsync();
        await missingAction.Should().NotThrowAsync();
    }

    [Fact]
    public async Task ChangeEmail_Should_Create_EmailChange_Token_And_Outbox_Message_For_New_Address()
    {
        var now = new DateTime(2026, 1, 4, 0, 0, 0, DateTimeKind.Utc);
        var tenantId = Guid.NewGuid();
        var userId = Guid.NewGuid();
        var user = AuthTestDataBuilder.User()
            .WithId(userId)
            .WithTenant(tenantId)
            .WithIdentity("jane", "jane@example.com")
            .WithPasswordHash("old-hash")
            .Build();
        const string rawToken = "raw-email-change-token";
        var encodedToken = Uri.EscapeDataString(rawToken);

        var fixture = new LifecycleFixture(new FakeClock(now));
        fixture.UserRepository.Setup(repository => repository.GetByIdAsync(tenantId, userId, It.IsAny<CancellationToken>()))
            .ReturnsAsync(user);
        fixture.UserRepository.Setup(repository => repository.ExistsByEmailAsync(tenantId, "JANE.NEW@EXAMPLE.COM", It.IsAny<CancellationToken>()))
            .ReturnsAsync(false);
        fixture.PasswordHasher.Setup(hasher => hasher.VerifyHashedPassword(user, user.PasswordHash, "Str0ng!Pass123"))
            .Returns(PasswordVerificationResult.Success);
        fixture.TokenService.Setup(service => service.GenerateToken()).Returns(rawToken);
        fixture.TokenService.Setup(service => service.HashToken(rawToken)).Returns("email-change-token-hash");
        var sut = fixture.CreateChangeEmailHandler();

        await sut.Handle(
            new ChangeEmailCommand(tenantId, userId, "jane.new@example.com", user.Email!, "Str0ng!Pass123", "127.0.0.1", "unit-test", "corr", "trace"),
            CancellationToken.None);

        fixture.TokenRepository.Verify(repository => repository.AddAsync(
            It.Is<AuthVerificationToken>(token =>
                token.TenantId == tenantId &&
                token.UserId == userId &&
                token.Purpose == AuthVerificationTokenPurpose.EmailChange &&
                token.TokenHash == "email-change-token-hash" &&
                token.Target == "JANE.NEW@EXAMPLE.COM"),
            It.IsAny<CancellationToken>()), Times.Once);
        fixture.Outbox.Verify(outbox => outbox.AddAsync(
            It.IsAny<Guid>(),
            AuthEmailChangeRequestedV1.EventName,
            AuthEmailChangeRequestedV1.EventVersion,
            AuthEmailChangeRequestedV1.RoutingKey,
            "Norge360.Auth",
            It.Is<AuthEmailChangeRequestedV1>(evt =>
                evt.UserId == userId &&
                evt.TenantId == tenantId &&
                evt.CurrentEmail == "jane@example.com" &&
                evt.NewEmail == "jane.new@example.com" &&
                evt.Token == rawToken &&
                evt.ConfirmationUrl.Contains($"tenantId={tenantId:D}", StringComparison.Ordinal) &&
                evt.ConfirmationUrl.Contains($"userId={userId:D}", StringComparison.Ordinal) &&
                evt.ConfirmationUrl.Contains($"token={encodedToken}", StringComparison.Ordinal)),
            "corr",
            "trace",
            now,
            It.IsAny<CancellationToken>()), Times.Once);
    }

    [Fact]
    public async Task ResetPassword_Should_Reject_Invalid_Token()
    {
        var tenantId = Guid.NewGuid();
        var userId = Guid.NewGuid();
        var fixture = new LifecycleFixture(new FakeClock(new DateTime(2026, 1, 4, 0, 0, 0, DateTimeKind.Utc)));
        var existingUser = AuthTestDataBuilder.User()
            .WithId(userId)
            .WithTenant(tenantId)
            .WithIdentity("jane", "jane@example.com")
            .WithPasswordHash("old-hash")
            .Build();
        fixture.UserRepository.Setup(repository => repository.GetByIdAsync(tenantId, userId, It.IsAny<CancellationToken>()))
            .ReturnsAsync(existingUser);
        fixture.TokenRepository.Setup(repository => repository.GetValidAsync(
                tenantId,
                userId,
                AuthVerificationTokenPurpose.PasswordReset,
                "token-hash",
                It.IsAny<DateTime>(),
                It.IsAny<CancellationToken>()))
            .ReturnsAsync((AuthVerificationToken?)null);
        fixture.TokenService.Setup(service => service.HashToken("token")).Returns("token-hash");
        var sut = fixture.CreateResetPasswordHandler();

        var action = async () => await sut.Handle(
            new ResetPasswordCommand(tenantId, userId, "token", "NewPassword123!", null, null, null, null),
            CancellationToken.None);

        var exception = await action.Should().ThrowAsync<AuthApplicationException>();
        exception.Which.StatusCode.Should().Be((int)HttpStatusCode.BadRequest);
        exception.Which.ErrorCode.Should().Be("invalid_password_reset_token");
    }

    [Fact]
    public async Task ResetPassword_Should_Reject_Unknown_User_With_Invalid_Token_Error()
    {
        var tenantId = Guid.NewGuid();
        var userId = Guid.NewGuid();
        var fixture = new LifecycleFixture(new FakeClock(new DateTime(2026, 1, 4, 0, 0, 0, DateTimeKind.Utc)));
        fixture.UserRepository.Setup(repository => repository.GetByIdAsync(tenantId, userId, It.IsAny<CancellationToken>()))
            .ReturnsAsync((User?)null);
        var sut = fixture.CreateResetPasswordHandler();

        var action = async () => await sut.Handle(
            new ResetPasswordCommand(tenantId, userId, "token", "NewPassword123!", null, null, null, null),
            CancellationToken.None);

        var exception = await action.Should().ThrowAsync<AuthApplicationException>();
        exception.Which.StatusCode.Should().Be((int)HttpStatusCode.BadRequest);
        exception.Which.ErrorCode.Should().Be("invalid_password_reset_token");
    }

    [Fact]
    public async Task ResetPassword_Should_Revoke_All_Sessions_And_Evict_Token_State()
    {
        var now = new DateTime(2026, 1, 4, 0, 0, 0, DateTimeKind.Utc);
        var tenantId = Guid.NewGuid();
        var userId = Guid.NewGuid();
        var user = AuthTestDataBuilder.User()
            .WithId(userId)
            .WithTenant(tenantId)
            .WithIdentity("jane", "jane@example.com")
            .WithPasswordHash("old-hash")
            .Build();
        var token = new AuthVerificationToken
        {
            TenantId = tenantId,
            UserId = userId,
            Purpose = AuthVerificationTokenPurpose.PasswordReset,
            TokenHash = "token-hash",
            ExpiresAtUtc = now.AddMinutes(30)
        };

        var fixture = new LifecycleFixture(new FakeClock(now));
        fixture.UserRepository.Setup(repository => repository.GetByIdAsync(tenantId, userId, It.IsAny<CancellationToken>()))
            .ReturnsAsync(user);
        fixture.TokenRepository.Setup(repository => repository.GetValidAsync(
                tenantId,
                userId,
                AuthVerificationTokenPurpose.PasswordReset,
                "token-hash",
                now,
                It.IsAny<CancellationToken>()))
            .ReturnsAsync(token);
        fixture.TokenService.Setup(service => service.HashToken("token")).Returns("token-hash");
        fixture.PasswordHasher.Setup(hasher => hasher.HashPassword(user, "NewPassword123!")).Returns("new-password-hash");
        var revokedSessionIds = new[] { Guid.NewGuid(), Guid.NewGuid() };
        fixture.UserSessionRepository.Setup(repository => repository.RevokeAllAsync(
                tenantId,
                userId,
                now,
                "password_reset",
                null,
                It.IsAny<CancellationToken>()))
            .ReturnsAsync(revokedSessionIds);

        var sut = fixture.CreateResetPasswordHandler();

        await sut.Handle(new ResetPasswordCommand(tenantId, userId, "token", "NewPassword123!", "127.0.0.1", "unit-test", "corr", "trace"), CancellationToken.None);

        token.IsConsumed.Should().BeTrue();
        user.PasswordHash.Should().Be("new-password-hash");
        user.TokenVersion.Should().Be(1);
        fixture.UserSessionRepository.Verify(repository => repository.RevokeAllAsync(
            tenantId,
            userId,
            now,
            "password_reset",
            null,
            It.IsAny<CancellationToken>()), Times.Once);
        fixture.UserTokenStateValidator.Verify(validator => validator.Evict(tenantId, userId), Times.Once);
        foreach (var sessionId in revokedSessionIds)
        {
            fixture.UserSessionStateValidator.Verify(validator => validator.Evict(tenantId, sessionId), Times.Once);
        }
    }

    [Fact]
    public async Task ChangePassword_Should_Evict_Revoked_Session_State_When_RevokeOtherSessions_Is_Enabled()
    {
        var now = new DateTime(2026, 1, 4, 0, 0, 0, DateTimeKind.Utc);
        var tenantId = Guid.NewGuid();
        var userId = Guid.NewGuid();
        var excludedSessionId = Guid.NewGuid();
        var user = AuthTestDataBuilder.User()
            .WithId(userId)
            .WithTenant(tenantId)
            .WithIdentity("jane", "jane@example.com")
            .WithPasswordHash("old-password-hash")
            .Build();
        var revokedSessionIds = new[] { Guid.NewGuid(), Guid.NewGuid() };

        var fixture = new LifecycleFixture(new FakeClock(now));
        fixture.UserRepository.Setup(repository => repository.GetByIdAsync(tenantId, userId, It.IsAny<CancellationToken>()))
            .ReturnsAsync(user);
        fixture.PasswordHasher.Setup(hasher => hasher.VerifyHashedPassword(user, "old-password-hash", "CurrentPassword123!"))
            .Returns(PasswordVerificationResult.Success);
        fixture.PasswordHasher.Setup(hasher => hasher.HashPassword(user, "NewPassword123!"))
            .Returns("new-password-hash");
        fixture.UserSessionRepository.Setup(repository => repository.RevokeAllAsync(
                tenantId,
                userId,
                now,
                "password_changed",
                excludedSessionId,
                It.IsAny<CancellationToken>()))
            .ReturnsAsync(revokedSessionIds);

        var sut = fixture.CreateChangePasswordHandler();

        await sut.Handle(
            new ChangePasswordCommand(
                tenantId,
                userId,
                "CurrentPassword123!",
                "NewPassword123!",
                RevokeOtherSessions: true,
                ExcludedSessionId: excludedSessionId,
                "127.0.0.1",
                "unit-test",
                "corr",
                "trace"),
            CancellationToken.None);

        user.PasswordHash.Should().Be("new-password-hash");
        user.TokenVersion.Should().Be(1);
        fixture.UserTokenStateValidator.Verify(validator => validator.Evict(tenantId, userId), Times.Once);
        foreach (var sessionId in revokedSessionIds)
        {
            fixture.UserSessionStateValidator.Verify(validator => validator.Evict(tenantId, sessionId), Times.Once);
        }
    }

    [Fact]
    public async Task ConfirmEmail_Should_Confirm_User_When_Token_Is_Valid()
    {
        var now = new DateTime(2026, 1, 4, 0, 0, 0, DateTimeKind.Utc);
        var tenantId = Guid.NewGuid();
        var userId = Guid.NewGuid();
        var user = AuthTestDataBuilder.User()
            .WithId(userId)
            .WithTenant(tenantId)
            .WithIdentity("jane", "jane@example.com")
            .Build();
        user.EmailConfirmed = false;

        var token = new AuthVerificationToken
        {
            TenantId = tenantId,
            UserId = userId,
            Purpose = AuthVerificationTokenPurpose.EmailConfirmation,
            TokenHash = "confirm-token-hash",
            ExpiresAtUtc = now.AddMinutes(30)
        };

        var fixture = new LifecycleFixture(new FakeClock(now));
        fixture.UserRepository.Setup(repository => repository.GetByIdAsync(tenantId, userId, It.IsAny<CancellationToken>()))
            .ReturnsAsync(user);
        fixture.TokenRepository.Setup(repository => repository.GetValidAsync(
                tenantId,
                userId,
                AuthVerificationTokenPurpose.EmailConfirmation,
                "confirm-token-hash",
                now,
                It.IsAny<CancellationToken>()))
            .ReturnsAsync(token);
        fixture.TokenService.Setup(service => service.HashToken("confirm-token"))
            .Returns("confirm-token-hash");

        var sut = fixture.CreateConfirmEmailHandler();

        await sut.Handle(new ConfirmEmailCommand(tenantId, userId, "confirm-token", "127.0.0.1", "unit-test", "corr", "trace"), CancellationToken.None);

        token.IsConsumed.Should().BeTrue();
        user.EmailConfirmed.Should().BeTrue();
        user.EmailConfirmedAt.Should().Be(now);
        fixture.AuditTrail.Verify(trail => trail.WriteAsync(
            It.Is<Norge360.Auth.Application.Records.AuthAuditRecord>(record => record.EventType == "auth.email.confirmed"),
            It.IsAny<CancellationToken>()), Times.Once);
    }

    [Fact]
    public async Task ConfirmEmail_Should_Reject_Unknown_User_With_Invalid_Token_Error()
    {
        var now = new DateTime(2026, 1, 4, 0, 0, 0, DateTimeKind.Utc);
        var tenantId = Guid.NewGuid();
        var userId = Guid.NewGuid();
        var fixture = new LifecycleFixture(new FakeClock(now));
        fixture.UserRepository.Setup(repository => repository.GetByIdAsync(tenantId, userId, It.IsAny<CancellationToken>()))
            .ReturnsAsync((User?)null);

        var sut = fixture.CreateConfirmEmailHandler();

        var action = async () => await sut.Handle(
            new ConfirmEmailCommand(tenantId, userId, "confirm-token", null, null, null, null),
            CancellationToken.None);

        var exception = await action.Should().ThrowAsync<AuthApplicationException>();
        exception.Which.StatusCode.Should().Be((int)HttpStatusCode.BadRequest);
        exception.Which.ErrorCode.Should().Be("invalid_email_confirmation_token");
    }

    [Fact]
    public async Task ConfirmEmail_Should_Reject_Invalid_Or_Expired_Token()
    {
        var now = new DateTime(2026, 1, 4, 0, 0, 0, DateTimeKind.Utc);
        var tenantId = Guid.NewGuid();
        var userId = Guid.NewGuid();
        var user = AuthTestDataBuilder.User()
            .WithId(userId)
            .WithTenant(tenantId)
            .WithIdentity("jane", "jane@example.com")
            .Build();
        var fixture = new LifecycleFixture(new FakeClock(now));
        fixture.UserRepository.Setup(repository => repository.GetByIdAsync(tenantId, userId, It.IsAny<CancellationToken>()))
            .ReturnsAsync(user);
        fixture.TokenRepository.Setup(repository => repository.GetValidAsync(
                tenantId,
                userId,
                AuthVerificationTokenPurpose.EmailConfirmation,
                "confirm-token-hash",
                now,
                It.IsAny<CancellationToken>()))
            .ReturnsAsync((AuthVerificationToken?)null);
        fixture.TokenService.Setup(service => service.HashToken("confirm-token"))
            .Returns("confirm-token-hash");

        var sut = fixture.CreateConfirmEmailHandler();

        var action = async () => await sut.Handle(
            new ConfirmEmailCommand(tenantId, userId, "confirm-token", null, null, null, null),
            CancellationToken.None);

        var exception = await action.Should().ThrowAsync<AuthApplicationException>();
        exception.Which.StatusCode.Should().Be((int)HttpStatusCode.BadRequest);
        exception.Which.ErrorCode.Should().Be("invalid_email_confirmation_token");
    }

    [Fact]
    public async Task ConfirmEmail_Should_Allow_Already_Confirmed_User_When_Token_Is_Valid()
    {
        var now = new DateTime(2026, 1, 4, 0, 0, 0, DateTimeKind.Utc);
        var tenantId = Guid.NewGuid();
        var userId = Guid.NewGuid();
        var user = AuthTestDataBuilder.User()
            .WithId(userId)
            .WithTenant(tenantId)
            .WithIdentity("jane", "jane@example.com")
            .Build();
        user.EmailConfirmed = true;
        user.EmailConfirmedAt = now.AddDays(-1);

        var token = new AuthVerificationToken
        {
            TenantId = tenantId,
            UserId = userId,
            Purpose = AuthVerificationTokenPurpose.EmailConfirmation,
            TokenHash = "confirm-token-hash",
            ExpiresAtUtc = now.AddMinutes(30)
        };

        var fixture = new LifecycleFixture(new FakeClock(now));
        fixture.UserRepository.Setup(repository => repository.GetByIdAsync(tenantId, userId, It.IsAny<CancellationToken>()))
            .ReturnsAsync(user);
        fixture.TokenRepository.Setup(repository => repository.GetValidAsync(
                tenantId,
                userId,
                AuthVerificationTokenPurpose.EmailConfirmation,
                "confirm-token-hash",
                now,
                It.IsAny<CancellationToken>()))
            .ReturnsAsync(token);
        fixture.TokenService.Setup(service => service.HashToken("confirm-token"))
            .Returns("confirm-token-hash");

        var sut = fixture.CreateConfirmEmailHandler();

        await sut.Handle(new ConfirmEmailCommand(tenantId, userId, "confirm-token", null, null, null, null), CancellationToken.None);

        token.IsConsumed.Should().BeTrue();
        user.EmailConfirmed.Should().BeTrue();
    }

    [Fact]
    public async Task ResendConfirmation_Should_Not_Enqueue_Email_When_TargetCooldown_Is_Active()
    {
        var tenantId = Guid.NewGuid();
        var user = AuthTestDataBuilder.User().WithTenant(tenantId).WithIdentity("jane", "jane@example.com").Build();
        var fixture = new LifecycleFixture(new FakeClock(new DateTime(2026, 1, 4, 0, 0, 0, DateTimeKind.Utc)));
        fixture.UserRepository.Setup(repository => repository.FindByTenantAndIdentityAsync(tenantId, user.NormalizedEmail, It.IsAny<CancellationToken>()))
            .ReturnsAsync(user);
        fixture.CooldownStore.Setup(store => store.TryAcquireAsync("email-confirmation-resend", tenantId, user.NormalizedEmail, It.IsAny<int>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(false);

        var sut = fixture.CreateResendEmailConfirmationHandler();

        await sut.Handle(new ResendEmailConfirmationCommand(tenantId, user.Email!, null, null, null, null), CancellationToken.None);

        fixture.TokenRepository.Verify(repository => repository.AddAsync(It.IsAny<AuthVerificationToken>(), It.IsAny<CancellationToken>()), Times.Never);
        fixture.Outbox.Verify(outbox => outbox.AddAsync(
            It.IsAny<Guid>(),
            It.IsAny<string>(),
            It.IsAny<int>(),
            It.IsAny<string>(),
            It.IsAny<string>(),
            It.IsAny<AuthEmailConfirmationRequestedV1>(),
            It.IsAny<string>(),
            It.IsAny<string>(),
            It.IsAny<DateTime>(),
            It.IsAny<CancellationToken>()), Times.Never);
        fixture.AuthUnitOfWork.Verify(unitOfWork => unitOfWork.SaveChangesAsync(It.IsAny<CancellationToken>()), Times.Never);
    }

    [Fact]
    public async Task ResendConfirmation_Should_Remain_Enumeration_Safe_When_Cooldown_Is_Active()
    {
        var tenantId = Guid.NewGuid();
        var existingUser = AuthTestDataBuilder.User().WithTenant(tenantId).WithIdentity("jane", "jane@example.com").Build();
        var fixture = new LifecycleFixture(new FakeClock(new DateTime(2026, 1, 4, 0, 0, 0, DateTimeKind.Utc)));
        fixture.UserRepository.Setup(repository => repository.FindByTenantAndIdentityAsync(tenantId, "JANE@EXAMPLE.COM", It.IsAny<CancellationToken>()))
            .ReturnsAsync(existingUser);
        fixture.UserRepository.Setup(repository => repository.FindByTenantAndIdentityAsync(tenantId, "MISSING@EXAMPLE.COM", It.IsAny<CancellationToken>()))
            .ReturnsAsync((User?)null);
        fixture.CooldownStore.Setup(store => store.TryAcquireAsync("email-confirmation-resend", tenantId, "JANE@EXAMPLE.COM", It.IsAny<int>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(false);

        var sut = fixture.CreateResendEmailConfirmationHandler();

        var existingAction = async () => await sut.Handle(new ResendEmailConfirmationCommand(tenantId, "jane@example.com", null, null, null, null), CancellationToken.None);
        var missingAction = async () => await sut.Handle(new ResendEmailConfirmationCommand(tenantId, "missing@example.com", null, null, null, null), CancellationToken.None);

        await existingAction.Should().NotThrowAsync();
        await missingAction.Should().NotThrowAsync();
    }

    private sealed class LifecycleFixture
    {
        private readonly FakeClock clock;

        public Mock<IUserRepository> UserRepository { get; } = new();
        public Mock<IAuthVerificationTokenRepository> TokenRepository { get; } = new();
        public Mock<IAuthVerificationTokenService> TokenService { get; } = new();
        public Mock<IAccountTargetCooldownStore> CooldownStore { get; } = new();
        public Mock<IIntegrationEventOutbox> Outbox { get; } = new();
        public Mock<IAuthAuditTrail> AuditTrail { get; } = new();
        public Mock<IAuthUnitOfWork> AuthUnitOfWork { get; } = new();
        public Mock<IUserSessionRepository> UserSessionRepository { get; } = new();
        public Mock<IPasswordHasher<User>> PasswordHasher { get; } = new();
        public Mock<IUserTokenStateValidator> UserTokenStateValidator { get; } = new();
        public Mock<IUserSessionStateValidator> UserSessionStateValidator { get; } = new();

        public LifecycleFixture(FakeClock clock)
        {
            this.clock = clock;
            TokenService.Setup(service => service.GenerateToken()).Returns("fixture-token");
            TokenService.Setup(service => service.HashToken(It.IsAny<string>())).Returns("fixture-token-hash");
            CooldownStore.Setup(store => store.TryAcquireAsync(
                    It.IsAny<string>(),
                    It.IsAny<Guid>(),
                    It.IsAny<string>(),
                    It.IsAny<int>(),
                    It.IsAny<CancellationToken>()))
                .ReturnsAsync(true);
        }

        public ForgotPasswordCommandHandler CreateForgotPasswordHandler() =>
            new(
                UserRepository.Object,
                TokenRepository.Object,
                TokenService.Object,
                CooldownStore.Object,
                Outbox.Object,
                AuditTrail.Object,
                AuthUnitOfWork.Object,
                clock,
                Microsoft.Extensions.Options.Options.Create(new AccountLifecycleOptions
                {
                    PublicAppBaseUrl = "https://auth.example.com",
                    ResetPasswordPath = "/reset-password",
                    PasswordResetTokenMinutes = 30
                }));

        public ResetPasswordCommandHandler CreateResetPasswordHandler() =>
            new(
                UserRepository.Object,
                UserSessionRepository.Object,
                TokenRepository.Object,
                TokenService.Object,
                PasswordHasher.Object,
                AuditTrail.Object,
                AuthUnitOfWork.Object,
                UserTokenStateValidator.Object,
                UserSessionStateValidator.Object,
                clock);

        public ConfirmEmailCommandHandler CreateConfirmEmailHandler() =>
            new(
                UserRepository.Object,
                TokenRepository.Object,
                TokenService.Object,
                AuditTrail.Object,
                AuthUnitOfWork.Object,
                clock);

        public ChangePasswordCommandHandler CreateChangePasswordHandler() =>
            new(
                UserRepository.Object,
                UserSessionRepository.Object,
                PasswordHasher.Object,
                AuditTrail.Object,
                AuthUnitOfWork.Object,
                UserTokenStateValidator.Object,
                UserSessionStateValidator.Object,
                clock);

        public ChangeEmailCommandHandler CreateChangeEmailHandler() =>
            new(
                UserRepository.Object,
                TokenRepository.Object,
                TokenService.Object,
                Outbox.Object,
                PasswordHasher.Object,
                AuditTrail.Object,
                AuthUnitOfWork.Object,
                clock,
                Microsoft.Extensions.Options.Options.Create(new AccountLifecycleOptions
                {
                    PublicAppBaseUrl = "https://auth.example.com",
                    ConfirmEmailChangePath = "/confirm-email-change",
                    EmailChangeTokenMinutes = 30
                }));

        public ResendEmailConfirmationCommandHandler CreateResendEmailConfirmationHandler() =>
            new(
                UserRepository.Object,
                TokenRepository.Object,
                TokenService.Object,
                CooldownStore.Object,
                Outbox.Object,
                AuditTrail.Object,
                AuthUnitOfWork.Object,
                clock,
                Microsoft.Extensions.Options.Options.Create(new AccountLifecycleOptions
                {
                    PublicAppBaseUrl = "https://auth.example.com",
                    ConfirmEmailPath = "/confirm-email",
                    EmailConfirmationTokenMinutes = 60
                }));
    }
}
