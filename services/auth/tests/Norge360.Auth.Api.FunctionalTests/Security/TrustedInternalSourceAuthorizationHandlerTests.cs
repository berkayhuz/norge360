// <copyright file="TrustedInternalSourceAuthorizationHandlerTests.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using System.Security.Claims;
using FluentAssertions;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Options;
using Norge360.AspNetCore.TrustedGateway.Options;
using Norge360.Auth.API.Middlewares;
using Norge360.Auth.API.Security;

namespace Norge360.Auth.Api.FunctionalTests.Security;

public sealed class TrustedInternalSourceAuthorizationHandlerTests
{
    [Fact]
    public async Task HandleRequirementAsync_Should_Fail_When_HttpContext_Is_Null()
    {
        var contextAccessor = new HttpContextAccessor { HttpContext = null };
        var sut = CreateSut(contextAccessor, requireTrustedGateway: false, allowedSources: ["internal-gateway"]);
        var authContext = CreateAuthorizationContext();

        await sut.HandleAsync(authContext);

        authContext.HasSucceeded.Should().BeFalse();
    }

    [Fact]
    public async Task HandleRequirementAsync_Should_Fail_When_Trusted_Gateway_Is_Required_And_Request_Not_Trusted()
    {
        var httpContext = new DefaultHttpContext();
        httpContext.Request.Headers["X-Source"] = "internal-gateway";

        var sut = CreateSut(
            new HttpContextAccessor { HttpContext = httpContext },
            requireTrustedGateway: true,
            allowedSources: ["internal-gateway"]);
        var authContext = CreateAuthorizationContext();

        await sut.HandleAsync(authContext);

        authContext.HasSucceeded.Should().BeFalse();
    }

    [Fact]
    public async Task HandleRequirementAsync_Should_Fail_When_Source_Header_Is_Missing()
    {
        var httpContext = new DefaultHttpContext();
        httpContext.Items[TrustedGatewayMiddleware.TrustedGatewayValidatedItemName] = true;

        var sut = CreateSut(
            new HttpContextAccessor { HttpContext = httpContext },
            requireTrustedGateway: true,
            allowedSources: ["internal-gateway"]);
        var authContext = CreateAuthorizationContext();

        await sut.HandleAsync(authContext);

        authContext.HasSucceeded.Should().BeFalse();
    }

    [Fact]
    public async Task HandleRequirementAsync_Should_Fail_When_Source_Not_In_Allowed_List()
    {
        var httpContext = new DefaultHttpContext();
        httpContext.Items[TrustedGatewayMiddleware.TrustedGatewayValidatedItemName] = true;
        httpContext.Request.Headers["X-Source"] = "unknown-source";

        var sut = CreateSut(
            new HttpContextAccessor { HttpContext = httpContext },
            requireTrustedGateway: true,
            allowedSources: ["internal-gateway"]);
        var authContext = CreateAuthorizationContext();

        await sut.HandleAsync(authContext);

        authContext.HasSucceeded.Should().BeFalse();
    }

    [Fact]
    public async Task HandleRequirementAsync_Should_Succeed_When_Trusted_And_Source_Allowed()
    {
        var httpContext = new DefaultHttpContext();
        httpContext.Items[TrustedGatewayMiddleware.TrustedGatewayValidatedItemName] = true;
        httpContext.Request.Headers["X-Source"] = "internal-gateway";

        var sut = CreateSut(
            new HttpContextAccessor { HttpContext = httpContext },
            requireTrustedGateway: true,
            allowedSources: ["internal-gateway"]);
        var authContext = CreateAuthorizationContext();

        await sut.HandleAsync(authContext);

        authContext.HasSucceeded.Should().BeTrue();
    }

    private static TrustedInternalSourceAuthorizationHandler CreateSut(
        IHttpContextAccessor accessor,
        bool requireTrustedGateway,
        string[] allowedSources)
    {
        var internalIdentityOptions = Options.Create(new InternalIdentityOptions
        {
            AllowedSources = allowedSources
        });

        var trustedGatewayOptions = Options.Create(new TrustedGatewayOptions
        {
            RequireTrustedGateway = requireTrustedGateway,
            SourceHeaderName = "X-Source"
        });

        return new TrustedInternalSourceAuthorizationHandler(accessor, internalIdentityOptions, trustedGatewayOptions);
    }

    private static AuthorizationHandlerContext CreateAuthorizationContext()
    {
        var principal = new ClaimsPrincipal(new ClaimsIdentity(authenticationType: "test"));
        return new AuthorizationHandlerContext([new TrustedInternalSourceRequirement()], principal, resource: null);
    }
}
