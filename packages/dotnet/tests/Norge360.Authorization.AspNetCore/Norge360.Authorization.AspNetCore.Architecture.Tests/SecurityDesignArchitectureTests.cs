// <copyright file="SecurityDesignArchitectureTests.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

namespace Norge360.Authorization.AspNetCore.Architecture.Tests;

public class SecurityDesignArchitectureTests
{
    [Fact]
    public void Permission_authorization_handler_should_remain_sealed()
    {
        Assert.True(
            typeof(Norge360.Authorization.AspNetCore.PermissionAuthorizationHandler).IsSealed,
            "PermissionAuthorizationHandler should remain sealed to keep security behavior explicit.");
    }

    [Fact]
    public void Permission_requirement_should_not_expose_mutable_state()
    {
        var requirement = typeof(Norge360.Authorization.AspNetCore.PermissionRequirement);
        var hasWritableProperty = requirement.GetProperties().Any(p => p.SetMethod is not null && p.SetMethod.IsPublic);
        Assert.False(hasWritableProperty, "PermissionRequirement should remain immutable.");
    }
}
