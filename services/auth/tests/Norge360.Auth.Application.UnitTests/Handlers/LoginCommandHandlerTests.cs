// <copyright file="LoginCommandHandlerTests.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using System.Net;
using FluentAssertions;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Identity;
using Microsoft.Extensions.Options;
using Moq;
using Norge360.Auth.Application.Abstractions;
using Norge360.Auth.Application.Descriptors;
using Norge360.Auth.Application.Exceptions;
using Norge360.Auth.Application.Features.Commands;
using Norge360.Auth.Application.Features.Handlers;
using Norge360.Auth.Application.Options;
using Norge360.Auth.Domain.Entities;
using Norge360.Auth.TestKit.Builders;
using Norge360.Auth.TestKit.Fakes;

namespace Norge360.Auth.Application.UnitTests.Handlers;

public sealed class LoginCommandHandlerTests
{
    [Fact]
    public async Task Handle_Should_Reject_Unknown_User_As_InvalidCredentials()
    {
        var now = new DateTime(2026, 1, 2, 12, 0, 0, DateTimeKind.Utc);
        var tenantId = Guid.NewGuid();
        var command = new LoginCommand(tenantId, "unknown@example.com", "StrongPassword123!", false, null, null, "127.0.0.1", "unit-test");

        var fixture = CreateFixture(now);
        fixture.TenantRepository.Setup(repository => repository.GetByIdAsync(tenantId, It.IsAny<CancellationToken>()))
            .ReturnsAsync(new Tenant { Id = tenantId, IsActive = true });
        fixture.UserRepository.Setup(repository => repository.FindByTenantAndIdentityAsync(tenantId, "UNKNOWN@EXAMPLE.COM", It.IsAny<CancellationToken>()))
            .ReturnsAsync((User?)null);

        var sut = fixture.CreateSut(requireConfirmedEmailForLogin: false);

        var action = async () => await sut.Handle(command, CancellationToken.None);

        var exception = await action.Should().ThrowAsync<AuthApplicationException>();
        exception.Which.StatusCode.Should().Be((int)HttpStatusCode.Unauthorized);
        exception.Which.ErrorCode.Should().Be("invalid_credentials");
    }

    [Fact]
    public async Task Handle_Should_Reject_Unconfirmed_Email_When_Required()
    {
        var now = new DateTime(2026, 1, 2, 12, 0, 0, DateTimeKind.Utc);
        var tenantId = Guid.NewGuid();
        var user = AuthTestDataBuilder.User().WithTenant(tenantId).Build();
        user.EmailConfirmed = false;
        var membership = AuthTestDataBuilder.Membership(tenantId, user.Id);
        var command = new LoginCommand(tenantId, user.Email!, "StrongPassword123!", false, null, null, "127.0.0.1", "unit-test");

        var fixture = CreateFixture(now);
        fixture.TenantRepository.Setup(repository => repository.GetByIdAsync(tenantId, It.IsAny<CancellationToken>()))
            .ReturnsAsync(new Tenant { Id = tenantId, IsActive = true });
        fixture.UserRepository.Setup(repository => repository.FindByTenantAndIdentityAsync(tenantId, user.NormalizedEmail, It.IsAny<CancellationToken>()))
            .ReturnsAsync(user);
        fixture.UserRepository.Setup(repository => repository.GetMembershipAsync(tenantId, user.Id, It.IsAny<CancellationToken>()))
            .ReturnsAsync(membership);

        var sut = fixture.CreateSut(requireConfirmedEmailForLogin: true);

        var action = async () => await sut.Handle(command, CancellationToken.None);

        var exception = await action.Should().ThrowAsync<AuthApplicationException>();
        exception.Which.StatusCode.Should().Be((int)HttpStatusCode.Forbidden);
        exception.Which.ErrorCode.Should().Be("email_confirmation_required");
    }

    [Fact]
    public async Task Handle_Should_Require_Mfa_When_User_Has_Mfa_And_No_Challenge_Data()
    {
        var now = new DateTime(2026, 1, 2, 12, 0, 0, DateTimeKind.Utc);
        var tenantId = Guid.NewGuid();
        var user = AuthTestDataBuilder.User().WithTenant(tenantId).Build();
        user.EmailConfirmed = true;
        user.MfaEnabled = true;
        var membership = AuthTestDataBuilder.Membership(tenantId, user.Id);
        var command = new LoginCommand(tenantId, user.Email!, "StrongPassword123!", false, null, null, "127.0.0.1", "unit-test");

        var fixture = CreateFixture(now);
        fixture.TenantRepository.Setup(repository => repository.GetByIdAsync(tenantId, It.IsAny<CancellationToken>()))
            .ReturnsAsync(new Tenant { Id = tenantId, IsActive = true });
        fixture.UserRepository.Setup(repository => repository.FindByTenantAndIdentityAsync(tenantId, user.NormalizedEmail, It.IsAny<CancellationToken>()))
            .ReturnsAsync(user);
        fixture.UserRepository.Setup(repository => repository.GetMembershipAsync(tenantId, user.Id, It.IsAny<CancellationToken>()))
            .ReturnsAsync(membership);
        fixture.PasswordHasher.Setup(hasher => hasher.VerifyHashedPassword(user, user.PasswordHash, command.Password))
            .Returns(PasswordVerificationResult.Success);

        var sut = fixture.CreateSut(requireConfirmedEmailForLogin: false);

        var action = async () => await sut.Handle(command, CancellationToken.None);

        var exception = await action.Should().ThrowAsync<AuthApplicationException>();
        exception.Which.StatusCode.Should().Be((int)HttpStatusCode.Unauthorized);
        exception.Which.ErrorCode.Should().Be("mfa_required");
        fixture.UserSessionRepository.Verify(repository => repository.AddAsync(It.IsAny<UserSession>(), It.IsAny<CancellationToken>()), Times.Never);
    }

    [Fact]
    public async Task Handle_Should_Reject_Locked_User()
    {
        var now = new DateTime(2026, 1, 2, 12, 0, 0, DateTimeKind.Utc);
        var tenantId = Guid.NewGuid();
        var user = AuthTestDataBuilder.User().WithTenant(tenantId).Build();
        user.EmailConfirmed = true;
        user.IsLocked = true;
        user.LockoutEndAt = now.AddMinutes(30);
        var membership = AuthTestDataBuilder.Membership(tenantId, user.Id);
        var command = new LoginCommand(tenantId, user.Email!, "StrongPassword123!", false, null, null, "127.0.0.1", "unit-test");

        var fixture = CreateFixture(now);
        fixture.TenantRepository.Setup(repository => repository.GetByIdAsync(tenantId, It.IsAny<CancellationToken>()))
            .ReturnsAsync(new Tenant { Id = tenantId, IsActive = true });
        fixture.UserRepository.Setup(repository => repository.FindByTenantAndIdentityAsync(tenantId, user.NormalizedEmail, It.IsAny<CancellationToken>()))
            .ReturnsAsync(user);
        fixture.UserRepository.Setup(repository => repository.GetMembershipAsync(tenantId, user.Id, It.IsAny<CancellationToken>()))
            .ReturnsAsync(membership);

        var sut = fixture.CreateSut(requireConfirmedEmailForLogin: false);

        var action = async () => await sut.Handle(command, CancellationToken.None);

        var exception = await action.Should().ThrowAsync<AuthApplicationException>();
        exception.Which.ErrorCode.Should().Be("account_locked");
        exception.Which.StatusCode.Should().Be((int)HttpStatusCode.Forbidden);
    }

    [Fact]
    public async Task Handle_Should_Login_With_Recovery_Code_And_Propagate_CancellationToken()
    {
        var cancellationTokenSource = new CancellationTokenSource();
        var cancellationToken = cancellationTokenSource.Token;
        var now = new DateTime(2026, 1, 2, 12, 0, 0, DateTimeKind.Utc);
        var tenantId = Guid.NewGuid();
        var user = AuthTestDataBuilder.User().WithTenant(tenantId).Build();
        user.EmailConfirmed = true;
        user.MfaEnabled = true;
        var membership = AuthTestDataBuilder.Membership(tenantId, user.Id);
        var command = new LoginCommand(tenantId, user.Email!, "StrongPassword123!", false, null, "RECOVERY-CODE", "127.0.0.1", "unit-test");
        var refreshDescriptor = new RefreshTokenDescriptor("refresh-token", "refresh-token-hash", now.AddDays(14));
        var accessDescriptor = AuthTestDataBuilder.AccessTokenDescriptor();
        var evictedSession = Guid.NewGuid();

        var fixture = CreateFixture(now);
        fixture.TenantRepository.Setup(repository => repository.GetByIdAsync(tenantId, It.IsAny<CancellationToken>()))
            .ReturnsAsync(new Tenant { Id = tenantId, IsActive = true });
        fixture.UserRepository.Setup(repository => repository.FindByTenantAndIdentityAsync(tenantId, user.NormalizedEmail, It.IsAny<CancellationToken>()))
            .ReturnsAsync(user);
        fixture.UserRepository.Setup(repository => repository.GetMembershipAsync(tenantId, user.Id, It.IsAny<CancellationToken>()))
            .ReturnsAsync(membership);
        fixture.PasswordHasher.Setup(hasher => hasher.VerifyHashedPassword(user, user.PasswordHash, command.Password))
            .Returns(PasswordVerificationResult.Success);
        fixture.RecoveryCodeService.Setup(service => service.HashCode(tenantId, user.Id, "RECOVERY-CODE"))
            .Returns("hashed-recovery-code");
        fixture.RecoveryCodeRepository.Setup(repository => repository.ConsumeAsync(tenantId, user.Id, "hashed-recovery-code", now, It.IsAny<CancellationToken>()))
            .ReturnsAsync(true);
        fixture.RefreshTokenService.Setup(service => service.Generate(It.IsAny<bool>())).Returns(refreshDescriptor);
        fixture.AuthSessionService.Setup(service => service.EnforceSessionLimitsAsync(tenantId, user.Id, It.IsAny<Guid>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync([evictedSession]);
        fixture.AccessTokenFactory.Setup(factory => factory.Create(
                user.Id,
                user.UserName,
                user.Email!,
                user.TokenVersion,
                It.IsAny<IReadOnlyCollection<string>>(),
                It.IsAny<IReadOnlyCollection<string>>(),
                tenantId,
                It.IsAny<Guid>(),
                It.IsAny<DateTimeOffset?>(),
                It.IsAny<IReadOnlyCollection<string>?>()))
            .Returns(accessDescriptor);

        var sut = fixture.CreateSut(requireConfirmedEmailForLogin: false);

        var response = await sut.Handle(command, cancellationToken);

        response.AccessToken.Should().Be(accessDescriptor.Token);
        response.RefreshToken.Should().Be(refreshDescriptor.Token);
        fixture.UserSessionRepository.Verify(
            repository => repository.AddAsync(
                It.Is<UserSession>(session => session.RefreshTokenHash == refreshDescriptor.Hash && session.UserId == user.Id),
                cancellationToken),
            Times.Once);
        fixture.UserSessionStateValidator.Verify(validator => validator.Evict(tenantId, evictedSession), Times.Once);
    }

    [Fact]
    public async Task Handle_Should_Reject_Invalid_Mfa_Code()
    {
        var now = new DateTime(2026, 1, 2, 12, 0, 0, DateTimeKind.Utc);
        var tenantId = Guid.NewGuid();
        var user = AuthTestDataBuilder.User().WithTenant(tenantId).Build();
        user.EmailConfirmed = true;
        user.MfaEnabled = true;
        user.AuthenticatorKeyProtected = "protected-key";
        var membership = AuthTestDataBuilder.Membership(tenantId, user.Id);
        var command = new LoginCommand(tenantId, user.Email!, "StrongPassword123!", false, "123456", null, "127.0.0.1", "unit-test");

        var fixture = CreateFixture(now);
        fixture.TenantRepository.Setup(repository => repository.GetByIdAsync(tenantId, It.IsAny<CancellationToken>()))
            .ReturnsAsync(new Tenant { Id = tenantId, IsActive = true });
        fixture.UserRepository.Setup(repository => repository.FindByTenantAndIdentityAsync(tenantId, user.NormalizedEmail, It.IsAny<CancellationToken>()))
            .ReturnsAsync(user);
        fixture.UserRepository.Setup(repository => repository.GetMembershipAsync(tenantId, user.Id, It.IsAny<CancellationToken>()))
            .ReturnsAsync(membership);
        fixture.PasswordHasher.Setup(hasher => hasher.VerifyHashedPassword(user, user.PasswordHash, command.Password))
            .Returns(PasswordVerificationResult.Success);
        fixture.AuthenticatorKeyProtector.Setup(protector => protector.Unprotect("protected-key"))
            .Returns("shared-key");
        fixture.TotpService.Setup(service => service.VerifyCode("shared-key", "123456", now))
            .Returns(false);

        var sut = fixture.CreateSut(requireConfirmedEmailForLogin: false);

        var action = async () => await sut.Handle(command, CancellationToken.None);

        var exception = await action.Should().ThrowAsync<AuthApplicationException>();
        exception.Which.StatusCode.Should().Be((int)HttpStatusCode.Unauthorized);
        exception.Which.ErrorCode.Should().Be("invalid_mfa_code");
        fixture.UserSessionRepository.Verify(repository => repository.AddAsync(It.IsAny<UserSession>(), It.IsAny<CancellationToken>()), Times.Never);
    }

    [Fact]
    public async Task Handle_Should_Login_With_Valid_Mfa_Code()
    {
        var now = new DateTime(2026, 1, 2, 12, 0, 0, DateTimeKind.Utc);
        var tenantId = Guid.NewGuid();
        var user = AuthTestDataBuilder.User().WithTenant(tenantId).Build();
        user.EmailConfirmed = true;
        user.MfaEnabled = true;
        user.AuthenticatorKeyProtected = "protected-key";
        var membership = AuthTestDataBuilder.Membership(tenantId, user.Id);
        var command = new LoginCommand(tenantId, user.Email!, "StrongPassword123!", false, "123456", null, "127.0.0.1", "unit-test");
        var refreshDescriptor = new RefreshTokenDescriptor("refresh-token", "refresh-token-hash", now.AddDays(14));
        var accessDescriptor = AuthTestDataBuilder.AccessTokenDescriptor("access-token");

        var fixture = CreateFixture(now);
        fixture.TenantRepository.Setup(repository => repository.GetByIdAsync(tenantId, It.IsAny<CancellationToken>()))
            .ReturnsAsync(new Tenant { Id = tenantId, IsActive = true });
        fixture.UserRepository.Setup(repository => repository.FindByTenantAndIdentityAsync(tenantId, user.NormalizedEmail, It.IsAny<CancellationToken>()))
            .ReturnsAsync(user);
        fixture.UserRepository.Setup(repository => repository.GetMembershipAsync(tenantId, user.Id, It.IsAny<CancellationToken>()))
            .ReturnsAsync(membership);
        fixture.PasswordHasher.Setup(hasher => hasher.VerifyHashedPassword(user, user.PasswordHash, command.Password))
            .Returns(PasswordVerificationResult.Success);
        fixture.AuthenticatorKeyProtector.Setup(protector => protector.Unprotect("protected-key"))
            .Returns("shared-key");
        fixture.TotpService.Setup(service => service.VerifyCode("shared-key", "123456", now))
            .Returns(true);
        fixture.RefreshTokenService.Setup(service => service.Generate(It.IsAny<bool>())).Returns(refreshDescriptor);
        fixture.AccessTokenFactory.Setup(factory => factory.Create(
                user.Id,
                user.UserName,
                user.Email!,
                user.TokenVersion,
                It.IsAny<IReadOnlyCollection<string>>(),
                It.IsAny<IReadOnlyCollection<string>>(),
                tenantId,
                It.IsAny<Guid>(),
                It.IsAny<DateTimeOffset?>(),
                It.IsAny<IReadOnlyCollection<string>?>()))
            .Returns(accessDescriptor);

        var sut = fixture.CreateSut(requireConfirmedEmailForLogin: false);

        var response = await sut.Handle(command, CancellationToken.None);

        response.AccessToken.Should().Be("access-token");
        response.RefreshToken.Should().Be("refresh-token");
        fixture.UserSessionRepository.Verify(repository => repository.AddAsync(It.IsAny<UserSession>(), It.IsAny<CancellationToken>()), Times.Once);
    }

    [Fact]
    public async Task Handle_When_FirstActiveUserBootstrapChangesRoles_Should_Evict_TokenState()
    {
        var now = new DateTime(2026, 1, 2, 12, 0, 0, DateTimeKind.Utc);
        var tenantId = Guid.NewGuid();
        var user = AuthTestDataBuilder.User().WithTenant(tenantId).Build();
        user.EmailConfirmed = true;
        var membership = AuthTestDataBuilder.Membership(tenantId, user.Id);
        var command = new LoginCommand(tenantId, user.Email!, "StrongPassword123!", false, null, null, "127.0.0.1", "unit-test");
        var refreshDescriptor = new RefreshTokenDescriptor("refresh-token", "refresh-token-hash", now.AddDays(14));
        var accessDescriptor = AuthTestDataBuilder.AccessTokenDescriptor("access-token");

        var fixture = CreateFixture(now);
        fixture.TenantRepository.Setup(repository => repository.GetByIdAsync(tenantId, It.IsAny<CancellationToken>()))
            .ReturnsAsync(new Tenant { Id = tenantId, IsActive = true });
        fixture.UserRepository.Setup(repository => repository.FindByTenantAndIdentityAsync(tenantId, user.NormalizedEmail, It.IsAny<CancellationToken>()))
            .ReturnsAsync(user);
        fixture.UserRepository.Setup(repository => repository.GetMembershipAsync(tenantId, user.Id, It.IsAny<CancellationToken>()))
            .ReturnsAsync(membership);
        fixture.UserRepository.Setup(repository => repository.IsFirstActiveUserInTenantAsync(tenantId, user.Id, It.IsAny<CancellationToken>()))
            .ReturnsAsync(true);
        fixture.PasswordHasher.Setup(hasher => hasher.VerifyHashedPassword(user, user.PasswordHash, command.Password))
            .Returns(PasswordVerificationResult.Success);
        fixture.RefreshTokenService.Setup(service => service.Generate(It.IsAny<bool>())).Returns(refreshDescriptor);
        fixture.AccessTokenFactory.Setup(factory => factory.Create(
                user.Id,
                user.UserName,
                user.Email!,
                1,
                It.IsAny<IReadOnlyCollection<string>>(),
                It.IsAny<IReadOnlyCollection<string>>(),
                tenantId,
                It.IsAny<Guid>(),
                It.IsAny<DateTimeOffset?>(),
                It.IsAny<IReadOnlyCollection<string>?>()))
            .Returns(accessDescriptor);

        var sut = fixture.CreateSut(requireConfirmedEmailForLogin: false);

        await sut.Handle(command, CancellationToken.None);

        user.TokenVersion.Should().Be(1);
        membership.GetRoles().Should().Contain("tenant-owner");
        fixture.UserTokenStateValidator.Verify(validator => validator.Evict(tenantId, user.Id), Times.Once);
    }

    private static Fixture CreateFixture(DateTime now)
    {
        var fixture = new Fixture(new FakeClock(now));
        fixture.HttpContextAccessor.Setup(accessor => accessor.HttpContext).Returns(new DefaultHttpContext());
        fixture.AuthSessionService.Setup(service => service.EnforceSessionLimitsAsync(It.IsAny<Guid>(), It.IsAny<Guid>(), It.IsAny<Guid>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(Array.Empty<Guid>());
        return fixture;
    }

    private sealed class Fixture(FakeClock clock)
    {
        public Mock<ITenantRepository> TenantRepository { get; } = new();
        public Mock<IUserRepository> UserRepository { get; } = new();
        public Mock<IUserSessionRepository> UserSessionRepository { get; } = new();
        public Mock<IAuthUnitOfWork> AuthUnitOfWork { get; } = new();
        public Mock<IAuthAuditTrail> AuditTrail { get; } = new();
        public Mock<IPasswordHasher<User>> PasswordHasher { get; } = new();
        public Mock<IAccessTokenFactory> AccessTokenFactory { get; } = new();
        public Mock<IRefreshTokenService> RefreshTokenService { get; } = new();
        public Mock<IAuthSessionService> AuthSessionService { get; } = new();
        public Mock<ISecurityAlertPublisher> SecurityAlertPublisher { get; } = new();
        public Mock<IUserTokenStateValidator> UserTokenStateValidator { get; } = new();
        public Mock<IUserSessionStateValidator> UserSessionStateValidator { get; } = new();
        public Mock<IAuthenticatorTotpService> TotpService { get; } = new();
        public Mock<IAuthenticatorKeyProtector> AuthenticatorKeyProtector { get; } = new();
        public Mock<IRecoveryCodeService> RecoveryCodeService { get; } = new();
        public Mock<IUserMfaRecoveryCodeRepository> RecoveryCodeRepository { get; } = new();
        public Mock<IHttpContextAccessor> HttpContextAccessor { get; } = new();

        public LoginCommandHandler CreateSut(bool requireConfirmedEmailForLogin)
        {
            return new LoginCommandHandler(
                TenantRepository.Object,
                UserRepository.Object,
                UserSessionRepository.Object,
                AuthUnitOfWork.Object,
                AuditTrail.Object,
                PasswordHasher.Object,
                AccessTokenFactory.Object,
                RefreshTokenService.Object,
                clock,
                Microsoft.Extensions.Options.Options.Create(new IdentitySecurityOptions { MaxFailedAccessAttempts = 5, LockoutMinutes = 15 }),
                Microsoft.Extensions.Options.Options.Create(new AccountLifecycleOptions { RequireConfirmedEmailForLogin = requireConfirmedEmailForLogin }),
                Microsoft.Extensions.Options.Options.Create(new AuthorizationOptions
                {
                    BootstrapFirstUserAsTenantOwner = true,
                    BootstrapFirstUserRoles = ["tenant-owner", "tenant-user"],
                    BootstrapFirstUserPermissions = ["*"]
                }),
                AuthSessionService.Object,
                SecurityAlertPublisher.Object,
                UserTokenStateValidator.Object,
                UserSessionStateValidator.Object,
                TotpService.Object,
                AuthenticatorKeyProtector.Object,
                RecoveryCodeService.Object,
                RecoveryCodeRepository.Object,
                HttpContextAccessor.Object);
        }
    }
}
