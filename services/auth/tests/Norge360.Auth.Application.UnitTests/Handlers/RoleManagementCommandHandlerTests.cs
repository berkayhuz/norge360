// <copyright file="RoleManagementCommandHandlerTests.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using FluentAssertions;
using Moq;
using Norge360.Auth.Application.Abstractions;
using Norge360.Auth.Application.Features.Commands;
using Norge360.Auth.Application.Features.Handlers;
using Norge360.Auth.Application.Security;
using Norge360.Auth.Domain.Entities;
using Norge360.Auth.TestKit.Builders;

namespace Norge360.Auth.Application.UnitTests.Handlers;

public sealed class RoleManagementCommandHandlerTests
{
    [Fact]
    public async Task UpdateTenantMemberRoles_When_RolesChange_Should_Evict_TargetUserTokenState()
    {
        var tenantId = Guid.NewGuid();
        var actor = AuthTestDataBuilder.User()
            .WithTenant(tenantId)
            .WithIdentity("owner", "owner@example.com")
            .Build();
        var target = AuthTestDataBuilder.User()
            .WithTenant(tenantId)
            .WithIdentity("member", "member@example.com")
            .Build();
        var actorMembership = AuthTestDataBuilder.Membership(
            tenantId,
            actor.Id,
            roles: AuthorizationCatalog.Roles.TenantOwner,
            permissions: AuthorizationCatalog.WildcardPermission);
        var targetMembership = AuthTestDataBuilder.Membership(
            tenantId,
            target.Id,
            roles: AuthorizationCatalog.Roles.TenantUser,
            permissions: AuthorizationCatalog.Permissions.SessionSelf);

        var fixture = new Fixture();
        fixture.Users.Setup(repository => repository.GetActiveByIdAsync(tenantId, actor.Id, It.IsAny<CancellationToken>()))
            .ReturnsAsync(actor);
        fixture.Users.Setup(repository => repository.GetMembershipAsync(tenantId, actor.Id, It.IsAny<CancellationToken>()))
            .ReturnsAsync(actorMembership);
        fixture.Users.Setup(repository => repository.GetActiveByIdAsync(tenantId, target.Id, It.IsAny<CancellationToken>()))
            .ReturnsAsync(target);
        fixture.Users.Setup(repository => repository.GetMembershipAsync(tenantId, target.Id, It.IsAny<CancellationToken>()))
            .ReturnsAsync(targetMembership);
        fixture.Users.Setup(repository => repository.CountActiveUsersInRoleAsync(tenantId, AuthorizationCatalog.Roles.TenantOwner, It.IsAny<CancellationToken>()))
            .ReturnsAsync(2);

        var sut = fixture.CreateSut();

        var response = await sut.Handle(
            new UpdateTenantMemberRolesCommand(
                tenantId,
                target.Id,
                actor.Id,
                [AuthorizationCatalog.Roles.TenantAdmin],
                "127.0.0.1",
                "unit-test",
                "corr",
                "trace"),
            CancellationToken.None);

        response.Roles.Should().Contain(AuthorizationCatalog.Roles.TenantAdmin);
        target.TokenVersion.Should().Be(1);
        fixture.UserTokenStateValidator.Verify(validator => validator.Evict(tenantId, target.Id), Times.Once);
        fixture.UnitOfWork.Verify(unitOfWork => unitOfWork.SaveChangesAsync(It.IsAny<CancellationToken>()), Times.Once);
    }

    private sealed class Fixture
    {
        public Mock<IUserRepository> Users { get; } = new();
        public Mock<IAuthAuditTrail> AuditTrail { get; } = new();
        public Mock<IAuthUnitOfWork> UnitOfWork { get; } = new();
        public Mock<IUserTokenStateValidator> UserTokenStateValidator { get; } = new();

        public Fixture()
        {
            AuditTrail.Setup(trail => trail.WriteAsync(It.IsAny<Norge360.Auth.Application.Records.AuthAuditRecord>(), It.IsAny<CancellationToken>()))
                .Returns(Task.CompletedTask);
            UnitOfWork.Setup(unitOfWork => unitOfWork.SaveChangesAsync(It.IsAny<CancellationToken>()))
                .ReturnsAsync(1);
        }

        public UpdateTenantMemberRolesCommandHandler CreateSut() =>
            new(Users.Object, AuditTrail.Object, UnitOfWork.Object, UserTokenStateValidator.Object);
    }
}
