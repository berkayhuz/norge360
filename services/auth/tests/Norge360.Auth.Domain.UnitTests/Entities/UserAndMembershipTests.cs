// <copyright file="UserAndMembershipTests.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using FluentAssertions;
using Norge360.Auth.Domain.Entities;
using Norge360.Entities;

namespace Norge360.Auth.Domain.UnitTests.Entities;

public sealed class UserAndMembershipTests
{
    [Fact]
    public void User_GetRoles_Should_Return_Distinct_CaseInsensitive_Roles()
    {
        var user = new User
        {
            Roles = "user, User ,platform-admin,platform-admin"
        };

        var roles = user.GetRoles();

        roles.Should().BeEquivalentTo(["user", "platform-admin"]);
    }

    [Fact]
    public void User_GetPermissions_Should_Trim_And_Deduplicate()
    {
        var user = new User
        {
            Permissions = "session:self, profile:self,SESSION:SELF"
        };

        var permissions = user.GetPermissions();

        permissions.Should().BeEquivalentTo(["session:self", "profile:self"]);
    }

    [Fact]
    public void EntityBase_Activate_Deactivate_Should_Toggle_IsActive()
    {
        var entity = new TestEntity();

        entity.Deactivate();
        entity.IsActive.Should().BeFalse();

        entity.Activate();
        entity.IsActive.Should().BeTrue();
    }

    private sealed class TestEntity : EntityBase;
}
