// <copyright file="InvitationCommandHandlerTests.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using FluentAssertions;
using Microsoft.AspNetCore.Identity;
using Moq;
using Norge360.Auth.Application.Abstractions;
using Norge360.Auth.Application.Descriptors;
using Norge360.Auth.Application.Exceptions;
using Norge360.Auth.Application.Features.Commands;
using Norge360.Auth.Application.Features.Handlers;
using Norge360.Auth.Application.Options;
using Norge360.Auth.Application.Records;
using Norge360.Auth.Contracts.IntegrationEvents;
using Norge360.Auth.Domain.Entities;
using Norge360.Auth.TestKit.Builders;
using Norge360.Auth.TestKit.Fakes;

namespace Norge360.Auth.Application.UnitTests.Handlers;

public sealed class InvitationCommandHandlerTests
{
    [Fact]
    public async Task AcceptInvitation_When_Token_Is_Invalid_Should_Persist_Failed_Audit()
    {
        var now = new DateTime(2026, 1, 7, 10, 0, 0, DateTimeKind.Utc);
        var tenantId = Guid.NewGuid();
        var fixture = new AcceptInvitationFixture(new FakeClock(now));
        fixture.TenantRepository.Setup(repository => repository.GetByIdAsync(tenantId, It.IsAny<CancellationToken>()))
            .ReturnsAsync(AuthTestDataBuilder.Tenant(tenantId));
        fixture.InvitationRepository.Setup(repository => repository.GetPendingByTokenHashAsync(tenantId, "invite-token-hash", now, It.IsAny<CancellationToken>()))
            .ReturnsAsync((TenantInvitation?)null);

        var sut = fixture.CreateSut();

        var action = async () => await sut.Handle(
            new AcceptTenantInvitationCommand(
                tenantId,
                "invite-token",
                "invitee",
                "invitee@example.com",
                "Str0ng!Pass123",
                null,
                null,
                "127.0.0.1",
                "unit-test",
                "corr",
                "trace"),
            CancellationToken.None);

        var exception = await action.Should().ThrowAsync<AuthApplicationException>();
        exception.Which.ErrorCode.Should().Be("invalid_invitation");
        fixture.AuditTrail.Verify(trail => trail.WriteAsync(
            It.Is<Norge360.Auth.Application.Records.AuthAuditRecord>(record =>
                record.EventType == "auth.invitation.acceptance_failed" &&
                record.Outcome == "invalid_or_expired"),
            It.IsAny<CancellationToken>()), Times.Once);
        fixture.UnitOfWork.Verify(unitOfWork => unitOfWork.SaveChangesAsync(It.IsAny<CancellationToken>()), Times.Once);
        fixture.SessionRepository.Verify(repository => repository.AddAsync(It.IsAny<UserSession>(), It.IsAny<CancellationToken>()), Times.Never);
    }

    [Fact]
    public async Task AcceptInvitation_When_NewIdentityRequiresEmailConfirmation_Should_Not_Issue_Authenticated_Tokens()
    {
        var now = new DateTime(2026, 1, 7, 10, 0, 0, DateTimeKind.Utc);
        var tenantId = Guid.NewGuid();
        var inviterId = Guid.NewGuid();
        var invitation = AuthTestDataBuilder.Invitation(
            tenantId,
            inviterId,
            email: "invitee@example.com",
            tokenHash: "invite-token-hash",
            expiresAtUtc: now.AddDays(1));

        var fixture = new AcceptInvitationFixture(new FakeClock(now));
        fixture.TenantRepository.Setup(repository => repository.GetByIdAsync(tenantId, It.IsAny<CancellationToken>()))
            .ReturnsAsync(AuthTestDataBuilder.Tenant(tenantId));
        fixture.InvitationRepository.Setup(repository => repository.GetPendingByTokenHashAsync(tenantId, "invite-token-hash", now, It.IsAny<CancellationToken>()))
            .ReturnsAsync(invitation);
        fixture.UserRepository.Setup(repository => repository.FindByTenantAndIdentityAsync(tenantId, "INVITEE@EXAMPLE.COM", It.IsAny<CancellationToken>()))
            .ReturnsAsync((User?)null);
        fixture.UserRepository.Setup(repository => repository.FindByIdentityAsync(It.IsAny<string>(), It.IsAny<CancellationToken>()))
            .ThrowsAsync(new InvalidOperationException("Global identity lookup must not be used for tenant-scoped invitation acceptance."));
        fixture.UserRepository.Setup(repository => repository.ExistsByUserNameAsync(tenantId, "INVITEE", It.IsAny<CancellationToken>()))
            .ReturnsAsync(false);
        fixture.UserRepository.Setup(repository => repository.ExistsByEmailAsync(tenantId, "INVITEE@EXAMPLE.COM", It.IsAny<CancellationToken>()))
            .ReturnsAsync(false);
        fixture.UserRepository.Setup(repository => repository.GetMembershipAsync(tenantId, It.IsAny<Guid>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync((UserTenantMembership?)null);

        var sut = fixture.CreateSut();

        var response = await sut.Handle(
            new AcceptTenantInvitationCommand(
                tenantId,
                "invite-token",
                "invitee",
                "invitee@example.com",
                "Str0ng!Pass123",
                "Invitee",
                "Example",
                "127.0.0.1",
                "unit-test",
                "corr",
                "trace"),
            CancellationToken.None);

        response.Should().BeOfType<AuthSessionResult.PendingConfirmation>();
        invitation.AcceptedAtUtc.Should().Be(now);
        invitation.AcceptedByUserId.Should().NotBeNull();
        fixture.RefreshTokenService.Verify(service => service.Generate(It.IsAny<bool>()), Times.Never);
        fixture.SessionRepository.Verify(repository => repository.AddAsync(It.IsAny<UserSession>(), It.IsAny<CancellationToken>()), Times.Never);
        fixture.AccessTokenFactory.Verify(factory => factory.Create(
            It.IsAny<Guid>(),
            It.IsAny<string>(),
            It.IsAny<string>(),
            It.IsAny<int>(),
            It.IsAny<IReadOnlyCollection<string>>(),
            It.IsAny<IReadOnlyCollection<string>>(),
            It.IsAny<Guid>(),
            It.IsAny<Guid>()), Times.Never);
        fixture.Outbox.Verify(outbox => outbox.AddAsync(
            It.IsAny<Guid>(),
            AuthEmailConfirmationRequestedV1.EventName,
            AuthEmailConfirmationRequestedV1.EventVersion,
            AuthEmailConfirmationRequestedV1.RoutingKey,
            "Norge360.Auth",
            It.Is<AuthEmailConfirmationRequestedV1>(message =>
                message.Email == "invitee@example.com" &&
                message.Token == "email-confirm-token"),
            "corr",
            "trace",
            now,
            It.IsAny<CancellationToken>()), Times.Once);
    }

    [Fact]
    public async Task AcceptInvitation_When_ExistingConfirmedIdentityAccepts_Should_Issue_Authenticated_Tokens()
    {
        var now = new DateTime(2026, 1, 7, 10, 0, 0, DateTimeKind.Utc);
        var tenantId = Guid.NewGuid();
        var user = AuthTestDataBuilder.User()
            .WithTenant(tenantId)
            .WithIdentity("invitee", "invitee@example.com")
            .WithPasswordHash("existing-hash")
            .WithEmailConfirmed(now.AddDays(-1))
            .Build();
        var membership = AuthTestDataBuilder.Membership(tenantId, user.Id);
        var invitation = AuthTestDataBuilder.Invitation(
            tenantId,
            Guid.NewGuid(),
            email: "invitee@example.com",
            tokenHash: "invite-token-hash",
            expiresAtUtc: now.AddDays(1));

        var fixture = new AcceptInvitationFixture(new FakeClock(now));
        fixture.TenantRepository.Setup(repository => repository.GetByIdAsync(tenantId, It.IsAny<CancellationToken>()))
            .ReturnsAsync(AuthTestDataBuilder.Tenant(tenantId));
        fixture.InvitationRepository.Setup(repository => repository.GetPendingByTokenHashAsync(tenantId, "invite-token-hash", now, It.IsAny<CancellationToken>()))
            .ReturnsAsync(invitation);
        fixture.UserRepository.Setup(repository => repository.FindByTenantAndIdentityAsync(tenantId, "INVITEE@EXAMPLE.COM", It.IsAny<CancellationToken>()))
            .ReturnsAsync(user);
        fixture.UserRepository.Setup(repository => repository.FindByTenantAndIdentityAsync(tenantId, user.NormalizedUserName, It.IsAny<CancellationToken>()))
            .ReturnsAsync(user);
        fixture.UserRepository.Setup(repository => repository.GetMembershipAsync(tenantId, user.Id, It.IsAny<CancellationToken>()))
            .ReturnsAsync(membership);
        fixture.PasswordHasher.Setup(hasher => hasher.VerifyHashedPassword(user, "existing-hash", "Str0ng!Pass123"))
            .Returns(PasswordVerificationResult.Success);
        fixture.RefreshTokenService.Setup(service => service.Generate(It.IsAny<bool>()))
            .Returns(new RefreshTokenDescriptor("refresh-token", "refresh-token-hash", now.AddDays(14)));
        fixture.AccessTokenFactory.Setup(factory => factory.Create(
                user.Id,
                user.UserName,
                user.Email!,
                user.TokenVersion,
                It.IsAny<IReadOnlyCollection<string>>(),
                It.IsAny<IReadOnlyCollection<string>>(),
                tenantId,
                It.IsAny<Guid>()))
            .Returns(new AccessTokenDescriptor("access-token", now.AddMinutes(15)));

        var sut = fixture.CreateSut();

        var response = await sut.Handle(
            new AcceptTenantInvitationCommand(
                tenantId,
                "invite-token",
                "invitee",
                "invitee@example.com",
                "Str0ng!Pass123",
                null,
                null,
                null,
                null,
                null,
                null),
            CancellationToken.None);

        var issued = response.Should().BeOfType<AuthSessionResult.Issued>().Subject;
        issued.Tokens.AccessToken.Should().Be("access-token");
        issued.Tokens.RefreshToken.Should().Be("refresh-token");
        fixture.SessionRepository.Verify(repository => repository.AddAsync(It.IsAny<UserSession>(), It.IsAny<CancellationToken>()), Times.Once);
    }

    private sealed class AcceptInvitationFixture
    {
        private readonly FakeClock _clock;

        public Mock<ITenantRepository> TenantRepository { get; } = new();
        public Mock<IUserRepository> UserRepository { get; } = new();
        public Mock<IUserSessionRepository> SessionRepository { get; } = new();
        public Mock<ITenantInvitationRepository> InvitationRepository { get; } = new();
        public Mock<IAuthUnitOfWork> UnitOfWork { get; } = new();
        public Mock<IAuthAuditTrail> AuditTrail { get; } = new();
        public Mock<IIntegrationEventOutbox> Outbox { get; } = new();
        public Mock<IAuthVerificationTokenRepository> VerificationTokenRepository { get; } = new();
        public Mock<IAuthVerificationTokenService> TokenService { get; } = new();
        public Mock<IPasswordHasher<User>> PasswordHasher { get; } = new();
        public Mock<IAccessTokenFactory> AccessTokenFactory { get; } = new();
        public Mock<IRefreshTokenService> RefreshTokenService { get; } = new();
        public Mock<IAuthSessionService> AuthSessionService { get; } = new();
        public Mock<IUserSessionStateValidator> UserSessionStateValidator { get; } = new();

        public AcceptInvitationFixture(FakeClock clock)
        {
            _clock = clock;
            TokenService.Setup(service => service.HashToken("invite-token")).Returns("invite-token-hash");
            TokenService.Setup(service => service.GenerateToken()).Returns("email-confirm-token");
            TokenService.Setup(service => service.HashToken("email-confirm-token")).Returns("email-confirm-token-hash");
            PasswordHasher.Setup(hasher => hasher.HashPassword(It.IsAny<User>(), It.IsAny<string>())).Returns("new-password-hash");
            UserRepository.Setup(repository => repository.AddAsync(It.IsAny<User>(), It.IsAny<CancellationToken>())).Returns(Task.CompletedTask);
            UserRepository.Setup(repository => repository.AddMembershipAsync(It.IsAny<UserTenantMembership>(), It.IsAny<CancellationToken>())).Returns(Task.CompletedTask);
            SessionRepository.Setup(repository => repository.AddAsync(It.IsAny<UserSession>(), It.IsAny<CancellationToken>())).Returns(Task.CompletedTask);
            VerificationTokenRepository.Setup(repository => repository.AddAsync(It.IsAny<AuthVerificationToken>(), It.IsAny<CancellationToken>())).Returns(Task.CompletedTask);
            AuditTrail.Setup(trail => trail.WriteAsync(It.IsAny<Norge360.Auth.Application.Records.AuthAuditRecord>(), It.IsAny<CancellationToken>())).Returns(Task.CompletedTask);
            AuthSessionService.Setup(service => service.EnforceSessionLimitsAsync(It.IsAny<Guid>(), It.IsAny<Guid>(), It.IsAny<Guid>(), It.IsAny<CancellationToken>()))
                .ReturnsAsync(Array.Empty<Guid>());
            UnitOfWork.Setup(unitOfWork => unitOfWork.SaveChangesAsync(It.IsAny<CancellationToken>())).ReturnsAsync(1);
            Outbox.Setup(outbox => outbox.AddAsync(
                    It.IsAny<Guid>(),
                    It.IsAny<string>(),
                    It.IsAny<int>(),
                    It.IsAny<string>(),
                    It.IsAny<string>(),
                    It.IsAny<UserRegisteredV1>(),
                    It.IsAny<string>(),
                    It.IsAny<string>(),
                    It.IsAny<DateTime>(),
                    It.IsAny<CancellationToken>()))
                .Returns(Task.CompletedTask);
            Outbox.Setup(outbox => outbox.AddAsync(
                    It.IsAny<Guid>(),
                    It.IsAny<string>(),
                    It.IsAny<int>(),
                    It.IsAny<string>(),
                    It.IsAny<string>(),
                    It.IsAny<AuthEmailConfirmationRequestedV1>(),
                    It.IsAny<string>(),
                    It.IsAny<string>(),
                    It.IsAny<DateTime>(),
                    It.IsAny<CancellationToken>()))
                .Returns(Task.CompletedTask);
        }

        public AcceptTenantInvitationCommandHandler CreateSut() =>
            new(
                TenantRepository.Object,
                UserRepository.Object,
                SessionRepository.Object,
                InvitationRepository.Object,
                UnitOfWork.Object,
                AuditTrail.Object,
                Outbox.Object,
                VerificationTokenRepository.Object,
                TokenService.Object,
                PasswordHasher.Object,
                AccessTokenFactory.Object,
                RefreshTokenService.Object,
                _clock,
                Microsoft.Extensions.Options.Options.Create(new AccountLifecycleOptions
                {
                    RequireConfirmedEmailForLogin = true,
                    EmailConfirmationTokenMinutes = 60,
                    PublicAppBaseUrl = "https://auth.example.com",
                    ConfirmEmailPath = "/confirm-email"
                }),
                AuthSessionService.Object,
                UserSessionStateValidator.Object);
    }
}
