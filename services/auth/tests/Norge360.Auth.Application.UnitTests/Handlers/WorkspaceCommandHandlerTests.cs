// <copyright file="WorkspaceCommandHandlerTests.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using System.Net;
using FluentAssertions;
using Moq;
using Norge360.Auth.Application.Abstractions;
using Norge360.Auth.Application.Exceptions;
using Norge360.Auth.Application.Features.Commands;
using Norge360.Auth.Application.Features.Handlers;
using Norge360.Auth.Application.Records;
using Norge360.Auth.Domain.Entities;
using Norge360.Auth.TestKit.Builders;
using Norge360.Auth.TestKit.Fakes;

namespace Norge360.Auth.Application.UnitTests.Handlers;

public sealed class WorkspaceCommandHandlerTests
{
    [Fact]
    public async Task DeleteWorkspace_When_TargetIsCurrentTenant_Should_Reject()
    {
        var tenantId = Guid.NewGuid();
        var userId = Guid.NewGuid();
        var fixture = new DeleteFixture();
        var sut = fixture.CreateSut();

        var action = async () => await sut.Handle(CreateDeleteCommand(tenantId, tenantId, userId), CancellationToken.None);

        var exception = await action.Should().ThrowAsync<AuthApplicationException>();
        exception.Which.StatusCode.Should().Be((int)HttpStatusCode.Conflict);
        exception.Which.ErrorCode.Should().Be("active_workspace_delete_forbidden");
        fixture.Tenants.Verify(repository => repository.DeactivateAsync(It.IsAny<Tenant>(), It.IsAny<DateTime>(), It.IsAny<Guid>(), It.IsAny<CancellationToken>()), Times.Never);
    }

    [Fact]
    public async Task DeleteWorkspace_When_UserIsNotOwner_Should_Reject()
    {
        var currentTenantId = Guid.NewGuid();
        var targetTenantId = Guid.NewGuid();
        var userId = Guid.NewGuid();
        var fixture = new DeleteFixture();
        fixture.Tenants.Setup(repository => repository.GetByIdAsync(targetTenantId, It.IsAny<CancellationToken>()))
            .ReturnsAsync(AuthTestDataBuilder.Tenant(targetTenantId));
        fixture.Users.Setup(repository => repository.GetMembershipAsync(targetTenantId, userId, It.IsAny<CancellationToken>()))
            .ReturnsAsync(AuthTestDataBuilder.Membership(targetTenantId, userId));
        var sut = fixture.CreateSut();

        var action = async () => await sut.Handle(CreateDeleteCommand(currentTenantId, targetTenantId, userId), CancellationToken.None);

        var exception = await action.Should().ThrowAsync<AuthApplicationException>();
        exception.Which.StatusCode.Should().Be((int)HttpStatusCode.Forbidden);
        exception.Which.ErrorCode.Should().Be("workspace_delete_forbidden");
        fixture.Tenants.Verify(repository => repository.DeactivateAsync(It.IsAny<Tenant>(), It.IsAny<DateTime>(), It.IsAny<Guid>(), It.IsAny<CancellationToken>()), Times.Never);
    }

    [Fact]
    public async Task DeleteWorkspace_When_UserIsOwner_Should_DeactivateWorkspace()
    {
        var currentTenantId = Guid.NewGuid();
        var targetTenantId = Guid.NewGuid();
        var userId = Guid.NewGuid();
        var memberUserId = Guid.NewGuid();
        var targetTenant = AuthTestDataBuilder.Tenant(targetTenantId);
        var fixture = new DeleteFixture();
        fixture.Tenants.Setup(repository => repository.GetByIdAsync(targetTenantId, It.IsAny<CancellationToken>()))
            .ReturnsAsync(targetTenant);
        fixture.Users.Setup(repository => repository.GetMembershipAsync(targetTenantId, userId, It.IsAny<CancellationToken>()))
            .ReturnsAsync(AuthTestDataBuilder.Membership(targetTenantId, userId, roles: "tenant-owner,tenant-user"));
        fixture.Users.Setup(repository => repository.ListMembershipsByUserAsync(userId, It.IsAny<CancellationToken>()))
            .ReturnsAsync([
                new UserTenantMembershipSnapshot(currentTenantId, "Current", "current", userId, DateTime.UtcNow, null, true, ["tenant-owner"], ["*"]),
                new UserTenantMembershipSnapshot(targetTenantId, "Target", "target", userId, DateTime.UtcNow, null, true, ["tenant-owner"], ["*"])
            ]);
        fixture.Users.Setup(repository => repository.ListMembershipsByTenantAsync(targetTenantId, It.IsAny<CancellationToken>()))
            .ReturnsAsync([
                AuthTestDataBuilder.Membership(targetTenantId, userId, roles: "tenant-owner,tenant-user"),
                AuthTestDataBuilder.Membership(targetTenantId, memberUserId, roles: "tenant-user", permissions: "session:self")
            ]);
        fixture.SessionRepository.Setup(repository => repository.RevokeAllAsync(
                targetTenantId,
                userId,
                It.IsAny<DateTime>(),
                "tenant_deactivated",
                null,
                It.IsAny<CancellationToken>()))
            .ReturnsAsync([Guid.NewGuid()]);
        fixture.SessionRepository.Setup(repository => repository.RevokeAllAsync(
                targetTenantId,
                memberUserId,
                It.IsAny<DateTime>(),
                "tenant_deactivated",
                null,
                It.IsAny<CancellationToken>()))
            .ReturnsAsync([Guid.NewGuid()]);
        var sut = fixture.CreateSut();

        await sut.Handle(CreateDeleteCommand(currentTenantId, targetTenantId, userId), CancellationToken.None);

        fixture.Tenants.Verify(repository => repository.DeactivateAsync(targetTenant, It.IsAny<DateTime>(), userId, It.IsAny<CancellationToken>()), Times.Once);
        fixture.SessionRepository.Verify(repository => repository.RevokeAllAsync(
            targetTenantId,
            userId,
            It.IsAny<DateTime>(),
            "tenant_deactivated",
            null,
            It.IsAny<CancellationToken>()), Times.Once);
        fixture.SessionRepository.Verify(repository => repository.RevokeAllAsync(
            targetTenantId,
            memberUserId,
            It.IsAny<DateTime>(),
            "tenant_deactivated",
            null,
            It.IsAny<CancellationToken>()), Times.Once);
        fixture.UserTokenStateValidator.Verify(validator => validator.Evict(targetTenantId, userId), Times.Once);
        fixture.UserTokenStateValidator.Verify(validator => validator.Evict(targetTenantId, memberUserId), Times.Once);
        fixture.UserSessionStateValidator.Verify(
            validator => validator.Evict(targetTenantId, It.IsAny<Guid>()),
            Times.Exactly(2));
        fixture.UnitOfWork.Verify(unit => unit.SaveChangesAsync(It.IsAny<CancellationToken>()), Times.Once);
    }

    [Fact]
    public async Task SwitchWorkspace_When_UserIsInactive_Should_Deny_Without_Issuing_Session()
    {
        var tenantId = Guid.NewGuid();
        var user = AuthTestDataBuilder.User()
            .WithTenant(tenantId)
            .AsInactive()
            .Build();
        var fixture = new Fixture();
        fixture.Tenants.Setup(repository => repository.GetByIdAsync(tenantId, It.IsAny<CancellationToken>()))
            .ReturnsAsync(AuthTestDataBuilder.Tenant(tenantId));
        fixture.Users.Setup(repository => repository.GetActiveByIdAsync(tenantId, user.Id, It.IsAny<CancellationToken>()))
            .ReturnsAsync(user);

        var sut = fixture.CreateSut();

        var action = async () => await sut.Handle(CreateCommand(tenantId, user.Id), CancellationToken.None);

        var exception = await action.Should().ThrowAsync<AuthApplicationException>();
        exception.Which.StatusCode.Should().Be((int)HttpStatusCode.Forbidden);
        exception.Which.ErrorCode.Should().Be("workspace_membership_forbidden");
        fixture.RefreshTokenService.Verify(service => service.Generate(It.IsAny<bool>()), Times.Never);
        fixture.SessionRepository.Verify(repository => repository.AddAsync(It.IsAny<UserSession>(), It.IsAny<CancellationToken>()), Times.Never);
    }

    [Fact]
    public async Task SwitchWorkspace_When_TenantIsInactive_Should_Deny_Without_Issuing_Session()
    {
        var tenantId = Guid.NewGuid();
        var userId = Guid.NewGuid();
        var fixture = new Fixture();
        fixture.Tenants.Setup(repository => repository.GetByIdAsync(tenantId, It.IsAny<CancellationToken>()))
            .ReturnsAsync(AuthTestDataBuilder.Tenant(tenantId, isActive: false));

        var sut = fixture.CreateSut();

        var action = async () => await sut.Handle(CreateCommand(tenantId, userId), CancellationToken.None);

        var exception = await action.Should().ThrowAsync<AuthApplicationException>();
        exception.Which.StatusCode.Should().Be((int)HttpStatusCode.NotFound);
        exception.Which.ErrorCode.Should().Be("workspace_not_found");
        fixture.RefreshTokenService.Verify(service => service.Generate(It.IsAny<bool>()), Times.Never);
        fixture.SessionRepository.Verify(repository => repository.AddAsync(It.IsAny<UserSession>(), It.IsAny<CancellationToken>()), Times.Never);
    }

    [Fact]
    public async Task SwitchWorkspace_When_MembershipIsInactive_Should_Deny_Without_Issuing_Session()
    {
        var tenantId = Guid.NewGuid();
        var user = AuthTestDataBuilder.User()
            .WithTenant(tenantId)
            .Build();
        var fixture = new Fixture();
        fixture.Tenants.Setup(repository => repository.GetByIdAsync(tenantId, It.IsAny<CancellationToken>()))
            .ReturnsAsync(AuthTestDataBuilder.Tenant(tenantId));
        fixture.Users.Setup(repository => repository.GetActiveByIdAsync(tenantId, user.Id, It.IsAny<CancellationToken>()))
            .ReturnsAsync(user);
        fixture.Users.Setup(repository => repository.GetMembershipAsync(tenantId, user.Id, It.IsAny<CancellationToken>()))
            .ReturnsAsync(AuthTestDataBuilder.Membership(tenantId, user.Id, isActive: false));

        var sut = fixture.CreateSut();

        var action = async () => await sut.Handle(CreateCommand(tenantId, user.Id), CancellationToken.None);

        var exception = await action.Should().ThrowAsync<AuthApplicationException>();
        exception.Which.StatusCode.Should().Be((int)HttpStatusCode.Forbidden);
        exception.Which.ErrorCode.Should().Be("workspace_membership_forbidden");
        fixture.RefreshTokenService.Verify(service => service.Generate(It.IsAny<bool>()), Times.Never);
        fixture.SessionRepository.Verify(repository => repository.AddAsync(It.IsAny<UserSession>(), It.IsAny<CancellationToken>()), Times.Never);
    }

    [Fact]
    public async Task SwitchWorkspace_When_MembershipIsMissing_Should_Deny_Without_Issuing_Session()
    {
        var tenantId = Guid.NewGuid();
        var user = AuthTestDataBuilder.User()
            .WithTenant(tenantId)
            .Build();
        var fixture = new Fixture();
        fixture.Tenants.Setup(repository => repository.GetByIdAsync(tenantId, It.IsAny<CancellationToken>()))
            .ReturnsAsync(AuthTestDataBuilder.Tenant(tenantId));
        fixture.Users.Setup(repository => repository.GetActiveByIdAsync(tenantId, user.Id, It.IsAny<CancellationToken>()))
            .ReturnsAsync(user);
        fixture.Users.Setup(repository => repository.GetMembershipAsync(tenantId, user.Id, It.IsAny<CancellationToken>()))
            .ReturnsAsync((UserTenantMembership?)null);

        var sut = fixture.CreateSut();

        var action = async () => await sut.Handle(CreateCommand(tenantId, user.Id), CancellationToken.None);

        var exception = await action.Should().ThrowAsync<AuthApplicationException>();
        exception.Which.StatusCode.Should().Be((int)HttpStatusCode.Forbidden);
        exception.Which.ErrorCode.Should().Be("workspace_membership_forbidden");
        fixture.RefreshTokenService.Verify(service => service.Generate(It.IsAny<bool>()), Times.Never);
        fixture.SessionRepository.Verify(repository => repository.AddAsync(It.IsAny<UserSession>(), It.IsAny<CancellationToken>()), Times.Never);
    }

    private static SwitchWorkspaceCommand CreateCommand(Guid targetTenantId, Guid userId) =>
        new(Guid.NewGuid(), targetTenantId, userId, "127.0.0.1", "unit-test", "corr", "trace");

    private static DeleteWorkspaceCommand CreateDeleteCommand(Guid currentTenantId, Guid targetTenantId, Guid userId) =>
        new(currentTenantId, targetTenantId, userId, "127.0.0.1", "unit-test", "corr", "trace");

    private sealed class DeleteFixture
    {
        private readonly FakeClock _clock = new(new DateTime(2026, 1, 8, 0, 0, 0, DateTimeKind.Utc));

        public Mock<ITenantRepository> Tenants { get; } = new();
        public Mock<IUserRepository> Users { get; } = new();
        public Mock<IUserSessionRepository> SessionRepository { get; } = new();
        public Mock<IAuthUnitOfWork> UnitOfWork { get; } = new();
        public Mock<IAuthAuditTrail> AuditTrail { get; } = new();
        public Mock<IUserTokenStateValidator> UserTokenStateValidator { get; } = new();
        public Mock<IUserSessionStateValidator> UserSessionStateValidator { get; } = new();

        public DeleteFixture()
        {
            AuditTrail.Setup(auditTrail => auditTrail.WriteAsync(It.IsAny<AuthAuditRecord>(), It.IsAny<CancellationToken>()))
                .Returns(Task.CompletedTask);
            UnitOfWork.Setup(unit => unit.SaveChangesAsync(It.IsAny<CancellationToken>()))
                .ReturnsAsync(1);
        }

        public DeleteWorkspaceCommandHandler CreateSut() =>
            new(
                Tenants.Object,
                Users.Object,
                SessionRepository.Object,
                UnitOfWork.Object,
                AuditTrail.Object,
                UserTokenStateValidator.Object,
                UserSessionStateValidator.Object,
                _clock);
    }

    private sealed class Fixture
    {
        private readonly FakeClock _clock = new(new DateTime(2026, 1, 8, 0, 0, 0, DateTimeKind.Utc));

        public Mock<ITenantRepository> Tenants { get; } = new();
        public Mock<IUserRepository> Users { get; } = new();
        public Mock<IUserSessionRepository> SessionRepository { get; } = new();
        public Mock<IAuthUnitOfWork> UnitOfWork { get; } = new();
        public Mock<IAuthAuditTrail> AuditTrail { get; } = new();
        public Mock<IAccessTokenFactory> AccessTokenFactory { get; } = new();
        public Mock<IRefreshTokenService> RefreshTokenService { get; } = new();
        public Mock<IAuthSessionService> AuthSessionService { get; } = new();
        public Mock<IUserSessionStateValidator> UserSessionStateValidator { get; } = new();

        public SwitchWorkspaceCommandHandler CreateSut() =>
            new(
                Tenants.Object,
                Users.Object,
                SessionRepository.Object,
                UnitOfWork.Object,
                AuditTrail.Object,
                AccessTokenFactory.Object,
                RefreshTokenService.Object,
                AuthSessionService.Object,
                UserSessionStateValidator.Object,
                _clock);
    }
}
