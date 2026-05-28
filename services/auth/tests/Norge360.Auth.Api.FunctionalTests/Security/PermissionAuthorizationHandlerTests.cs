// <copyright file="PermissionAuthorizationHandlerTests.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using System.Security.Claims;
using FluentAssertions;
using Microsoft.AspNetCore.Authorization;
using Norge360.Auth.API.Permissions;

namespace Norge360.Auth.Api.FunctionalTests.Security;

public sealed class PermissionAuthorizationHandlerTests
{
    private readonly PermissionAuthorizationHandler _sut = new();

    [Fact]
    public async Task HandleRequirementAsync_Should_Succeed_When_Tenant_Claim_Valid_And_Wildcard_Permission_Exists()
    {
        var context = CreateContext(
            new Claim("tenant_id", Guid.NewGuid().ToString("D")),
            new Claim("permission", "*"));

        await _sut.HandleAsync(context);

        context.HasSucceeded.Should().BeTrue();
    }

    [Fact]
    public async Task HandleRequirementAsync_Should_Succeed_When_Tenant_Claim_Valid_And_Specific_Permission_Exists()
    {
        var context = CreateContext(
            new Claim("tenant_id", Guid.NewGuid().ToString("D")),
            new Claim("permission", "auth:users:read"),
            requiredPermission: "auth:users:read");

        await _sut.HandleAsync(context);

        context.HasSucceeded.Should().BeTrue();
    }

    [Fact]
    public async Task HandleRequirementAsync_Should_Fail_When_Tenant_Claim_Is_Missing()
    {
        var context = CreateContext(new Claim("permission", "*"));

        await _sut.HandleAsync(context);

        context.HasSucceeded.Should().BeFalse();
    }

    [Fact]
    public async Task HandleRequirementAsync_Should_Fail_When_Tenant_Claim_Is_Not_A_Guid()
    {
        var context = CreateContext(
            new Claim("tenant_id", "not-a-guid"),
            new Claim("permission", "*"));

        await _sut.HandleAsync(context);

        context.HasSucceeded.Should().BeFalse();
    }

    [Fact]
    public async Task HandleRequirementAsync_Should_Fail_When_Tenant_Claim_Is_Empty_Guid()
    {
        var context = CreateContext(
            new Claim("tenant_id", Guid.Empty.ToString("D")),
            new Claim("permission", "*"));

        await _sut.HandleAsync(context);

        context.HasSucceeded.Should().BeFalse();
    }

    [Fact]
    public async Task HandleRequirementAsync_Should_Fail_When_Required_Permission_Does_Not_Exist()
    {
        var context = CreateContext(
            new Claim("tenant_id", Guid.NewGuid().ToString("D")),
            new Claim("permission", "auth:users:write"),
            requiredPermission: "auth:users:read");

        await _sut.HandleAsync(context);

        context.HasSucceeded.Should().BeFalse();
    }

    private static AuthorizationHandlerContext CreateContext(
        Claim claim,
        Claim? claim2 = null,
        string requiredPermission = "auth:users:read")
    {
        var claims = claim2 is null ? [claim] : new[] { claim, claim2 };
        var principal = new ClaimsPrincipal(new ClaimsIdentity(claims, "test"));

        return new AuthorizationHandlerContext(
            [new PermissionRequirement(requiredPermission)],
            principal,
            resource: null);
    }
}
