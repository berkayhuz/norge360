// <copyright file="RegisterCommandHandlerTests.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using System.Net;
using FluentAssertions;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
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
using Norge360.Auth.TestKit.Fakes;

namespace Norge360.Auth.Application.UnitTests.Handlers;

public sealed class RegisterCommandHandlerTests
{
    [Fact]
    public async Task Handle_Should_Map_DbUpdateException_To_RegistrationConflict()
    {
        var utcNow = new DateTime(2026, 1, 6, 8, 30, 0, DateTimeKind.Utc);
        var command = new RegisterCommand(
            "Acme Workspace",
            "berkay",
            "berkay@example.com",
            "Str0ng!Pass123",
            "Berkay",
            "Test",
            "en-US",
            "127.0.0.1",
            "unit-test");

        var fixture = new Fixture(utcNow);
        fixture.UseSaveConflict();
        var sut = fixture.CreateSut();

        var action = async () => await sut.Handle(command, CancellationToken.None);

        var exception = await action.Should().ThrowAsync<AuthApplicationException>();
        exception.Which.StatusCode.Should().Be((int)HttpStatusCode.Conflict);
        exception.Which.ErrorCode.Should().Be("registration_conflict");
    }

    [Fact]
    public async Task Handle_When_EmailConfirmation_Is_Required_Should_Not_Issue_Authenticated_Tokens()
    {
        var utcNow = new DateTime(2026, 1, 6, 8, 30, 0, DateTimeKind.Utc);
        var command = new RegisterCommand(
            "Acme Workspace",
            "berkay",
            "berkay@example.com",
            "Str0ng!Pass123",
            "Berkay",
            "Test",
            "en-US",
            "127.0.0.1",
            "unit-test");

        var fixture = new Fixture(utcNow);
        var sut = fixture.CreateSut();

        var response = await sut.Handle(command, CancellationToken.None);

        response.Should().BeOfType<AuthSessionResult.PendingConfirmation>();
        fixture.RefreshTokenService.Verify(service => service.Generate(It.IsAny<bool>()), Times.Never);
        fixture.UserSessionRepository.Verify(repository => repository.AddAsync(It.IsAny<UserSession>(), It.IsAny<CancellationToken>()), Times.Never);
        fixture.AccessTokenFactory.Verify(factory => factory.Create(It.IsAny<User>(), It.IsAny<Guid>(), It.IsAny<Guid>()), Times.Never);
        OutboxShouldContainEmailConfirmationEvent(fixture);
    }

    [Fact]
    public async Task Handle_Should_Create_User_Tenant_And_OwnerMembership_In_One_UnitOfWork()
    {
        var utcNow = new DateTime(2026, 1, 6, 8, 30, 0, DateTimeKind.Utc);
        var command = new RegisterCommand(
            "Acme Workspace",
            "berkay",
            "berkay@example.com",
            "Str0ng!Pass123",
            "Berkay",
            "Test",
            "en-US",
            "127.0.0.1",
            "unit-test");

        var fixture = new Fixture(utcNow);
        Tenant? createdTenant = null;
        User? createdUser = null;
        UserTenantMembership? createdMembership = null;
        fixture.TenantRepository
            .Setup(repository => repository.AddAsync(It.IsAny<Tenant>(), It.IsAny<CancellationToken>()))
            .Callback<Tenant, CancellationToken>((tenant, _) => createdTenant = tenant)
            .Returns(Task.CompletedTask);
        fixture.UserRepository
            .Setup(repository => repository.AddAsync(It.IsAny<User>(), It.IsAny<CancellationToken>()))
            .Callback<User, CancellationToken>((user, _) => createdUser = user)
            .Returns(Task.CompletedTask);
        fixture.UserRepository
            .Setup(repository => repository.AddMembershipAsync(It.IsAny<UserTenantMembership>(), It.IsAny<CancellationToken>()))
            .Callback<UserTenantMembership, CancellationToken>((membership, _) => createdMembership = membership)
            .Returns(Task.CompletedTask);
        var sut = fixture.CreateSut();

        await sut.Handle(command, CancellationToken.None);

        createdTenant.Should().NotBeNull();
        createdUser.Should().NotBeNull();
        createdMembership.Should().NotBeNull();
        createdUser!.TenantId.Should().Be(createdTenant!.Id);
        createdMembership!.TenantId.Should().Be(createdTenant.Id);
        createdMembership.UserId.Should().Be(createdUser.Id);
        createdMembership.Roles.Split(',').Should().Contain("tenant-owner");
        fixture.UnitOfWork.Verify(unitOfWork => unitOfWork.SaveChangesAsync(It.IsAny<CancellationToken>()), Times.Once);
    }

    [Fact]
    public async Task Handle_Should_Reject_Duplicate_Normalized_Email_Before_Creating_Tenant()
    {
        var utcNow = new DateTime(2026, 1, 6, 8, 30, 0, DateTimeKind.Utc);
        var command = new RegisterCommand(
            "Acme Workspace",
            "berkay",
            "Berkay@Example.com",
            "Str0ng!Pass123",
            "Berkay",
            "Test",
            "en-US",
            "127.0.0.1",
            "unit-test");

        var fixture = new Fixture(utcNow);
        fixture.UserRepository
            .Setup(repository => repository.ExistsByEmailAsync("BERKAY@EXAMPLE.COM", It.IsAny<CancellationToken>()))
            .ReturnsAsync(true);
        var sut = fixture.CreateSut();

        var action = async () => await sut.Handle(command, CancellationToken.None);

        var exception = await action.Should().ThrowAsync<AuthApplicationException>();
        exception.Which.StatusCode.Should().Be((int)HttpStatusCode.Conflict);
        exception.Which.ErrorCode.Should().Be("duplicate_email");
        fixture.TenantRepository.Verify(repository => repository.AddAsync(It.IsAny<Tenant>(), It.IsAny<CancellationToken>()), Times.Never);
        fixture.UserRepository.Verify(repository => repository.AddAsync(It.IsAny<User>(), It.IsAny<CancellationToken>()), Times.Never);
        fixture.UnitOfWork.Verify(unitOfWork => unitOfWork.SaveChangesAsync(It.IsAny<CancellationToken>()), Times.Never);
    }

    [Fact]
    public async Task Handle_Should_Normalize_Whitespace_And_Case_For_Duplicate_Email_Check()
    {
        var utcNow = new DateTime(2026, 1, 6, 8, 30, 0, DateTimeKind.Utc);
        var command = new RegisterCommand(
            "Acme Workspace",
            "berkay",
            "  User@Example.com  ",
            "Str0ng!Pass123",
            "Berkay",
            "Test",
            "en-US",
            "127.0.0.1",
            "unit-test");

        var fixture = new Fixture(utcNow);
        fixture.UserRepository
            .Setup(repository => repository.ExistsByEmailAsync("USER@EXAMPLE.COM", It.IsAny<CancellationToken>()))
            .ReturnsAsync(true);
        var sut = fixture.CreateSut();

        var action = async () => await sut.Handle(command, CancellationToken.None);

        var exception = await action.Should().ThrowAsync<AuthApplicationException>();
        exception.Which.ErrorCode.Should().Be("duplicate_email");
    }

    [Fact]
    public async Task Handle_When_EmailConfirmation_Is_Not_Required_Should_Issue_Authenticated_Tokens()
    {
        var utcNow = new DateTime(2026, 1, 6, 8, 30, 0, DateTimeKind.Utc);
        var command = new RegisterCommand(
            "Acme Workspace",
            "berkay",
            "berkay@example.com",
            "Str0ng!Pass123",
            "Berkay",
            "Test",
            "en-US",
            "127.0.0.1",
            "unit-test");

        var fixture = new Fixture(utcNow);
        fixture.AllowLoginBeforeEmailConfirmation();
        var sut = fixture.CreateSut();

        var response = await sut.Handle(command, CancellationToken.None);

        var issued = response.Should().BeOfType<AuthSessionResult.Issued>().Subject;
        issued.Tokens.AccessToken.Should().Be("access-token");
        issued.Tokens.RefreshToken.Should().Be("refresh-token");
        issued.Tokens.Email.Should().Be("berkay@example.com");
        fixture.UserSessionRepository.Verify(repository => repository.AddAsync(It.IsAny<UserSession>(), It.IsAny<CancellationToken>()), Times.Once);
    }

    private static void OutboxShouldContainEmailConfirmationEvent(Fixture fixture)
    {
        fixture.Outbox.Verify(outbox => outbox.AddAsync(
                It.IsAny<Guid>(),
                AuthEmailConfirmationRequestedV1.EventName,
                AuthEmailConfirmationRequestedV1.EventVersion,
                AuthEmailConfirmationRequestedV1.RoutingKey,
                "Norge360.Auth",
                It.Is<AuthEmailConfirmationRequestedV1>(message =>
                    message.Email == "berkay@example.com" &&
                    message.UserName == "berkay" &&
                    message.Token == "email-confirm-token"),
                It.IsAny<string>(),
                It.IsAny<string>(),
                It.IsAny<DateTime>(),
                It.IsAny<CancellationToken>()),
            Times.Once);
    }

    private sealed class Fixture
    {
        private readonly FakeClock _clock;

        public Fixture(DateTime utcNow)
        {
            _clock = new FakeClock(utcNow);

            TenantRepository.Setup(repository => repository.AddAsync(It.IsAny<Tenant>(), It.IsAny<CancellationToken>()))
                .Returns(Task.CompletedTask);
            UserRepository.Setup(repository => repository.AddAsync(It.IsAny<User>(), It.IsAny<CancellationToken>()))
                .Returns(Task.CompletedTask);
            UserRepository.Setup(repository => repository.ExistsByEmailAsync(It.IsAny<string>(), It.IsAny<CancellationToken>()))
                .ReturnsAsync(false);
            UserRepository.Setup(repository => repository.AddMembershipAsync(It.IsAny<UserTenantMembership>(), It.IsAny<CancellationToken>()))
                .Returns(Task.CompletedTask);
            UserSessionRepository.Setup(repository => repository.AddAsync(It.IsAny<UserSession>(), It.IsAny<CancellationToken>()))
                .Returns(Task.CompletedTask);
            VerificationTokenRepository.Setup(repository => repository.AddAsync(It.IsAny<AuthVerificationToken>(), It.IsAny<CancellationToken>()))
                .Returns(Task.CompletedTask);

            VerificationTokenService.Setup(service => service.GenerateToken()).Returns("email-confirm-token");
            VerificationTokenService.Setup(service => service.HashToken("email-confirm-token")).Returns("email-confirm-token-hash");
            PasswordHasher.Setup(hasher => hasher.HashPassword(It.IsAny<User>(), It.IsAny<string>())).Returns("hashed-password");
            RefreshTokenService.Setup(service => service.Generate(It.IsAny<bool>())).Returns(new RefreshTokenDescriptor("refresh-token", "refresh-token-hash", utcNow.AddDays(14)));
            AccessTokenFactory.Setup(factory => factory.Create(It.IsAny<User>(), It.IsAny<Guid>(), It.IsAny<Guid>()))
                .Returns(new AccessTokenDescriptor("access-token", utcNow.AddMinutes(15)));
            AuthSessionService.Setup(service => service.EnforceSessionLimitsAsync(It.IsAny<Guid>(), It.IsAny<Guid>(), It.IsAny<Guid>(), It.IsAny<CancellationToken>()))
                .ReturnsAsync(Array.Empty<Guid>());
            AuditTrail.Setup(trail => trail.WriteAsync(It.IsAny<Norge360.Auth.Application.Records.AuthAuditRecord>(), It.IsAny<CancellationToken>()))
                .Returns(Task.CompletedTask);
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

            UnitOfWork.Setup(unitOfWork => unitOfWork.SaveChangesAsync(It.IsAny<CancellationToken>()))
                .ReturnsAsync(1);
        }

        public Mock<ITenantRepository> TenantRepository { get; } = new();
        public Mock<IUserRepository> UserRepository { get; } = new();
        public Mock<IUserSessionRepository> UserSessionRepository { get; } = new();
        public Mock<IAuthUnitOfWork> UnitOfWork { get; } = new();
        public Mock<IAuthAuditTrail> AuditTrail { get; } = new();
        public Mock<IIntegrationEventOutbox> Outbox { get; } = new();
        public Mock<IAuthVerificationTokenRepository> VerificationTokenRepository { get; } = new();
        public Mock<IAuthVerificationTokenService> VerificationTokenService { get; } = new();
        public Mock<IPasswordHasher<User>> PasswordHasher { get; } = new();
        public Mock<IAccessTokenFactory> AccessTokenFactory { get; } = new();
        public Mock<IRefreshTokenService> RefreshTokenService { get; } = new();
        public Mock<IAuthSessionService> AuthSessionService { get; } = new();
        public Mock<IUserSessionStateValidator> UserSessionStateValidator { get; } = new();
        public Mock<IHttpContextAccessor> HttpContextAccessor { get; } = new();
        public AccountLifecycleOptions LifecycleOptions { get; } = new()
        {
            EmailConfirmationTokenMinutes = 60,
            PublicAppBaseUrl = "https://auth.example.com",
            ConfirmEmailPath = "/confirm-email"
        };

        public void UseSaveConflict()
        {
            UnitOfWork.Setup(unitOfWork => unitOfWork.SaveChangesAsync(It.IsAny<CancellationToken>()))
                .ThrowsAsync(new DbUpdateException("Unique constraint violation."));
        }

        public void AllowLoginBeforeEmailConfirmation()
        {
            LifecycleOptions.RequireConfirmedEmailForLogin = false;
        }

        public RegisterCommandHandler CreateSut() =>
            new(
                TenantRepository.Object,
                UserRepository.Object,
                UserSessionRepository.Object,
                UnitOfWork.Object,
                AuditTrail.Object,
                Outbox.Object,
                VerificationTokenRepository.Object,
                VerificationTokenService.Object,
                PasswordHasher.Object,
                AccessTokenFactory.Object,
                RefreshTokenService.Object,
                _clock,
                Microsoft.Extensions.Options.Options.Create(new AuthorizationOptions
                {
                    BootstrapFirstUserAsTenantOwner = true,
                    BootstrapFirstUserRoles = ["tenant-owner", "tenant-user"],
                    BootstrapFirstUserPermissions = ["*"]
                }),
                Microsoft.Extensions.Options.Options.Create(LifecycleOptions),
                AuthSessionService.Object,
                UserSessionStateValidator.Object,
                HttpContextAccessor.Object);
    }
}
