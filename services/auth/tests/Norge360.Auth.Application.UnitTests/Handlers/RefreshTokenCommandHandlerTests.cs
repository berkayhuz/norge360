// <copyright file="RefreshTokenCommandHandlerTests.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using System.Net;
using FluentAssertions;
using Microsoft.AspNetCore.Http;
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

public sealed class RefreshTokenCommandHandlerTests
{
    [Fact]
    public async Task Handle_Should_Revoke_Session_When_Mfa_Enabled_After_Session_Creation()
    {
        var now = new DateTime(2026, 1, 3, 12, 0, 0, DateTimeKind.Utc);
        var tenantId = Guid.NewGuid();
        var user = AuthTestDataBuilder.User().WithTenant(tenantId).WithEmailConfirmed().Build();
        user.MfaEnabled = true;
        user.MfaEnabledAt = now.AddMinutes(-5);
        var session = new UserSession
        {
            TenantId = tenantId,
            UserId = user.Id,
            CreatedAt = now.AddHours(-1),
            RefreshTokenHash = "stored-hash",
            RefreshTokenExpiresAt = now.AddDays(14),
            User = user
        };

        var fixture = new Fixture(new FakeClock(now));
        fixture.TenantRepository.Setup(repository => repository.GetByIdAsync(tenantId, It.IsAny<CancellationToken>()))
            .ReturnsAsync(new Tenant { Id = tenantId, IsActive = true });
        fixture.UserSessionRepository.Setup(repository => repository.GetWithUserAsync(tenantId, session.Id, It.IsAny<CancellationToken>()))
            .ReturnsAsync(session);
        fixture.AuthSessionService.Setup(service => service.IsExpired(session, now)).Returns(false);
        fixture.RefreshTokenService.Setup(service => service.Verify("refresh-token", session.RefreshTokenHash)).Returns(true);
        fixture.UserRepository.Setup(repository => repository.GetMembershipAsync(tenantId, user.Id, It.IsAny<CancellationToken>()))
            .ReturnsAsync(AuthTestDataBuilder.Membership(tenantId, user.Id));

        var sut = fixture.CreateSut();

        var action = async () => await sut.Handle(new RefreshTokenCommand(tenantId, session.Id, "refresh-token", null, null), CancellationToken.None);

        var exception = await action.Should().ThrowAsync<AuthApplicationException>();
        exception.Which.ErrorCode.Should().Be("invalid_refresh_token");
        exception.Which.StatusCode.Should().Be((int)HttpStatusCode.Unauthorized);
        session.IsRevoked.Should().BeTrue();
        session.RevokedReason.Should().Be("mfa_reauthentication_required");
        fixture.UserSessionStateValidator.Verify(validator => validator.Evict(tenantId, session.Id), Times.Once);
    }

    [Fact]
    public async Task Handle_Should_Detect_RefreshToken_Reuse_And_Evict_All_Session_State()
    {
        var now = new DateTime(2026, 1, 3, 12, 0, 0, DateTimeKind.Utc);
        var tenantId = Guid.NewGuid();
        var user = AuthTestDataBuilder.User().WithTenant(tenantId).WithEmailConfirmed().Build();
        var session = new UserSession
        {
            TenantId = tenantId,
            UserId = user.Id,
            CreatedAt = now.AddHours(-1),
            RefreshTokenHash = "stored-hash",
            RefreshTokenExpiresAt = now.AddDays(14)
        };
        var revokedSiblingSession = Guid.NewGuid();

        var fixture = new Fixture(new FakeClock(now));
        fixture.TenantRepository.Setup(repository => repository.GetByIdAsync(tenantId, It.IsAny<CancellationToken>()))
            .ReturnsAsync(new Tenant { Id = tenantId, IsActive = true });
        fixture.UserSessionRepository.Setup(repository => repository.GetWithUserAsync(tenantId, session.Id, It.IsAny<CancellationToken>()))
            .ReturnsAsync(session);
        fixture.AuthSessionService.Setup(service => service.IsExpired(session, now)).Returns(false);
        fixture.RefreshTokenService.Setup(service => service.Verify("invalid-refresh-token", session.RefreshTokenHash)).Returns(false);
        fixture.UserRepository.Setup(repository => repository.GetByIdAsync(tenantId, user.Id, It.IsAny<CancellationToken>()))
            .ReturnsAsync(user);
        fixture.UserSessionRepository.Setup(repository => repository.RevokeAllAsync(
                tenantId,
                user.Id,
                now,
                "refresh_token_reuse_detected",
                session.Id,
                It.IsAny<CancellationToken>()))
            .ReturnsAsync([revokedSiblingSession]);

        var sut = fixture.CreateSut();

        var action = async () => await sut.Handle(new RefreshTokenCommand(tenantId, session.Id, "invalid-refresh-token", "10.10.10.10", "unit-test"), CancellationToken.None);

        var exception = await action.Should().ThrowAsync<AuthApplicationException>();
        exception.Which.ErrorCode.Should().Be("invalid_refresh_token");
        user.TokenVersion.Should().Be(1);
        session.RefreshTokenReuseDetectedAt.Should().Be(now);
        fixture.UserTokenStateValidator.Verify(validator => validator.Evict(tenantId, user.Id), Times.Once);
        fixture.UserSessionStateValidator.Verify(validator => validator.Evict(tenantId, session.Id), Times.Once);
        fixture.UserSessionStateValidator.Verify(validator => validator.Evict(tenantId, revokedSiblingSession), Times.Once);
    }

    [Fact]
    public async Task Handle_Should_Revoke_Session_When_EmailConfirmation_Is_Required_And_User_Is_Unconfirmed()
    {
        var now = new DateTime(2026, 1, 3, 12, 0, 0, DateTimeKind.Utc);
        var tenantId = Guid.NewGuid();
        var user = AuthTestDataBuilder.User().WithTenant(tenantId).WithEmailConfirmed().Build();
        user.EmailConfirmed = false;
        var session = new UserSession
        {
            TenantId = tenantId,
            UserId = user.Id,
            CreatedAt = now.AddHours(-1),
            RefreshTokenHash = "stored-hash",
            RefreshTokenExpiresAt = now.AddDays(14),
            User = user
        };

        var fixture = new Fixture(new FakeClock(now));
        fixture.TenantRepository.Setup(repository => repository.GetByIdAsync(tenantId, It.IsAny<CancellationToken>()))
            .ReturnsAsync(new Tenant { Id = tenantId, IsActive = true });
        fixture.UserSessionRepository.Setup(repository => repository.GetWithUserAsync(tenantId, session.Id, It.IsAny<CancellationToken>()))
            .ReturnsAsync(session);
        fixture.AuthSessionService.Setup(service => service.IsExpired(session, now)).Returns(false);
        fixture.RefreshTokenService.Setup(service => service.Verify("refresh-token", session.RefreshTokenHash)).Returns(true);
        fixture.UserRepository.Setup(repository => repository.GetMembershipAsync(tenantId, user.Id, It.IsAny<CancellationToken>()))
            .ReturnsAsync(AuthTestDataBuilder.Membership(tenantId, user.Id));

        var sut = fixture.CreateSut();

        var action = async () => await sut.Handle(new RefreshTokenCommand(tenantId, session.Id, "refresh-token", null, null), CancellationToken.None);

        var exception = await action.Should().ThrowAsync<AuthApplicationException>();
        exception.Which.ErrorCode.Should().Be("invalid_refresh_token");
        session.IsRevoked.Should().BeTrue();
        session.RevokedReason.Should().Be("email_confirmation_required");
        fixture.UserSessionStateValidator.Verify(validator => validator.Evict(tenantId, session.Id), Times.Once);
        fixture.AccessTokenFactory.Verify(factory => factory.Create(
            It.IsAny<Guid>(),
            It.IsAny<string>(),
            It.IsAny<string>(),
            It.IsAny<int>(),
            It.IsAny<IReadOnlyCollection<string>>(),
            It.IsAny<IReadOnlyCollection<string>>(),
            It.IsAny<Guid>(),
            It.IsAny<Guid>(),
            It.IsAny<DateTimeOffset?>(),
            It.IsAny<IReadOnlyCollection<string>?>()), Times.Never);
    }

    [Fact]
    public async Task Handle_Should_Rotate_Token_On_Successful_Refresh()
    {
        var now = new DateTime(2026, 1, 3, 12, 0, 0, DateTimeKind.Utc);
        var tenantId = Guid.NewGuid();
        var user = AuthTestDataBuilder.User().WithTenant(tenantId).WithEmailConfirmed().Build();
        var membership = AuthTestDataBuilder.Membership(tenantId, user.Id);
        var session = new UserSession
        {
            TenantId = tenantId,
            UserId = user.Id,
            CreatedAt = now.AddHours(-1),
            RefreshTokenHash = "stored-hash",
            RefreshTokenExpiresAt = now.AddDays(14),
            User = user
        };
        var refreshDescriptor = new RefreshTokenDescriptor("new-refresh-token", "new-refresh-token-hash", now.AddDays(14));

        var fixture = new Fixture(new FakeClock(now));
        fixture.TenantRepository.Setup(repository => repository.GetByIdAsync(tenantId, It.IsAny<CancellationToken>()))
            .ReturnsAsync(new Tenant { Id = tenantId, IsActive = true });
        fixture.UserSessionRepository.Setup(repository => repository.GetWithUserAsync(tenantId, session.Id, It.IsAny<CancellationToken>()))
            .ReturnsAsync(session);
        fixture.AuthSessionService.Setup(service => service.IsExpired(session, now)).Returns(false);
        fixture.RefreshTokenService.Setup(service => service.Verify("current-refresh-token", session.RefreshTokenHash)).Returns(true);
        fixture.UserRepository.Setup(repository => repository.GetMembershipAsync(tenantId, user.Id, It.IsAny<CancellationToken>()))
            .ReturnsAsync(membership);
        fixture.RefreshTokenService.Setup(service => service.Generate(It.IsAny<bool>())).Returns(refreshDescriptor);
        fixture.AccessTokenFactory.Setup(factory => factory.Create(
                user.Id,
                user.UserName,
                user.Email!,
                user.TokenVersion,
                It.IsAny<IReadOnlyCollection<string>>(),
                It.IsAny<IReadOnlyCollection<string>>(),
                tenantId,
                session.Id,
                It.IsAny<DateTimeOffset?>(),
                It.IsAny<IReadOnlyCollection<string>?>()))
            .Returns(AuthTestDataBuilder.AccessTokenDescriptor("new-access-token"));

        var sut = fixture.CreateSut();

        var response = await sut.Handle(new RefreshTokenCommand(tenantId, session.Id, "current-refresh-token", null, null), CancellationToken.None);

        response.AccessToken.Should().Be("new-access-token");
        response.RefreshToken.Should().Be("new-refresh-token");
        session.RefreshTokenHash.Should().Be("new-refresh-token-hash");
        session.LastRefreshedAt.Should().Be(now);
        session.RefreshTokenReplacedAt.Should().Be(now);
    }

    private sealed class Fixture(FakeClock clock)
    {
        public Mock<ITenantRepository> TenantRepository { get; } = new();
        public Mock<IUserRepository> UserRepository { get; } = new();
        public Mock<IUserSessionRepository> UserSessionRepository { get; } = new();
        public Mock<IAuthUnitOfWork> AuthUnitOfWork { get; } = new();
        public Mock<IAuthAuditTrail> AuditTrail { get; } = new();
        public Mock<IAccessTokenFactory> AccessTokenFactory { get; } = new();
        public Mock<IRefreshTokenService> RefreshTokenService { get; } = new();
        public Mock<IAuthSessionService> AuthSessionService { get; } = new();
        public Mock<ISecurityAlertPublisher> SecurityAlertPublisher { get; } = new();
        public Mock<IUserTokenStateValidator> UserTokenStateValidator { get; } = new();
        public Mock<IUserSessionStateValidator> UserSessionStateValidator { get; } = new();
        public Mock<IHttpContextAccessor> HttpContextAccessor { get; } = new();

        public RefreshTokenCommandHandler CreateSut()
        {
            HttpContextAccessor.Setup(accessor => accessor.HttpContext).Returns(new DefaultHttpContext());
            UserRepository.Setup(repository => repository.GetMembershipAsync(It.IsAny<Guid>(), It.IsAny<Guid>(), It.IsAny<CancellationToken>()))
                .ReturnsAsync((Guid tenantId, Guid userId, CancellationToken _) => AuthTestDataBuilder.Membership(tenantId, userId));

            return new RefreshTokenCommandHandler(
                TenantRepository.Object,
                UserRepository.Object,
                UserSessionRepository.Object,
                AuthUnitOfWork.Object,
                AuditTrail.Object,
                AccessTokenFactory.Object,
                RefreshTokenService.Object,
                clock,
                AuthSessionService.Object,
                SecurityAlertPublisher.Object,
                UserTokenStateValidator.Object,
                UserSessionStateValidator.Object,
                HttpContextAccessor.Object,
                Microsoft.Extensions.Options.Options.Create(new AccountLifecycleOptions { RequireConfirmedEmailForLogin = true }));
        }
    }
}
