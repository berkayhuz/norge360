// <copyright file="AuthRequestContextAccessorTests.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using FluentAssertions;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Options;
using Moq;
using Norge360.Auth.API.Accessors;
using Norge360.Auth.API.Cookies;
using Norge360.Auth.Application.Abstractions;
using Norge360.Auth.Application.Exceptions;
using Norge360.Auth.Application.Options;
using Norge360.Auth.Application.Records;

namespace Norge360.Auth.Api.FunctionalTests.Security;

public sealed class AuthRequestContextAccessorTests
{
    [Fact]
    public void ResolveTenantId_Should_Return_ResolvedTenant_When_TrustedContext_ContainsTenantId()
    {
        var resolvedTenantId = Guid.NewGuid();
        var sut = CreateSut(
            new TenantContext(resolvedTenantId, null, "header", true),
            allowBodyFallback: false,
            tokenOptions: CreateTokenOptions());

        var tenantId = sut.ResolveTenantId(Guid.Empty);

        tenantId.Should().Be(resolvedTenantId);
    }

    [Fact]
    public void ResolveTenantId_Should_Throw_When_BodyTenant_Mismatches_TrustedTenant()
    {
        var sut = CreateSut(
            new TenantContext(Guid.NewGuid(), null, "header", true),
            allowBodyFallback: true,
            tokenOptions: CreateTokenOptions());

        var action = () => sut.ResolveTenantId(Guid.NewGuid());

        var exception = action.Should().Throw<AuthApplicationException>().Which;
        exception.ErrorCode.Should().Be("tenant_mismatch");
        exception.StatusCode.Should().Be(StatusCodes.Status400BadRequest);
    }

    [Fact]
    public void ResolveTenantId_Should_Throw_When_Tenant_Not_Resolved_And_BodyFallback_Disabled()
    {
        var sut = CreateSut(
            tenantContext: null,
            allowBodyFallback: false,
            tokenOptions: CreateTokenOptions());

        var action = () => sut.ResolveTenantId(Guid.NewGuid());

        var exception = action.Should().Throw<AuthApplicationException>().Which;
        exception.ErrorCode.Should().Be("tenant_resolution_required");
    }

    [Fact]
    public void ResolveRefreshContext_Should_Read_From_Cookies_When_Mode_Is_CookiesOnly()
    {
        var tokenOptions = CreateTokenOptions(mode: TokenTransportModes.CookiesOnly);
        var sut = CreateSut(null, allowBodyFallback: true, tokenOptions);
        var sessionId = Guid.NewGuid();
        var request = CreateHttpContextWithCookies(
            (tokenOptions.RefreshCookieName, "cookie-refresh"),
            (tokenOptions.SessionCookieName, sessionId.ToString("D"))).Request;

        var result = sut.ResolveRefreshContext(request, Guid.NewGuid(), "body-refresh");

        result.SessionId.Should().Be(sessionId);
        result.RefreshToken.Should().Be("cookie-refresh");
    }

    [Fact]
    public void ResolveRefreshContext_Should_Fallback_To_Body_When_Allowed_And_Cookie_Missing()
    {
        var tokenOptions = CreateTokenOptions(
            mode: TokenTransportModes.CookiesOnly,
            allowRefreshTokenFromBody: true,
            allowSessionIdFromBody: true);
        var sut = CreateSut(null, allowBodyFallback: true, tokenOptions);
        var requestedSessionId = Guid.NewGuid();
        var request = new DefaultHttpContext().Request;

        var result = sut.ResolveRefreshContext(request, requestedSessionId, "body-refresh");

        result.SessionId.Should().Be(requestedSessionId);
        result.RefreshToken.Should().Be("body-refresh");
    }

    [Fact]
    public void ResolveRefreshContext_Should_Use_Body_In_BodyOnly_Mode()
    {
        var tokenOptions = CreateTokenOptions(mode: TokenTransportModes.BodyOnly);
        var sut = CreateSut(null, allowBodyFallback: true, tokenOptions);
        var requestedSessionId = Guid.NewGuid();
        var request = new DefaultHttpContext().Request;

        var result = sut.ResolveRefreshContext(request, requestedSessionId, "body-refresh");

        result.SessionId.Should().Be(requestedSessionId);
        result.RefreshToken.Should().Be("body-refresh");
    }

    [Fact]
    public void GetPrincipalContext_Should_Parse_Valid_Claims()
    {
        var tenantId = Guid.NewGuid();
        var userId = Guid.NewGuid();
        var sessionId = Guid.NewGuid();
        var principal = new ClaimsPrincipal(new ClaimsIdentity(
        [
            new Claim("tenant_id", tenantId.ToString("D")),
            new Claim(ClaimTypes.NameIdentifier, userId.ToString("D")),
            new Claim(JwtRegisteredClaimNames.Sid, sessionId.ToString("D")),
            new Claim(ClaimTypes.Email, "user@norge360.test")
        ], "test"));

        var sut = CreateSut(null, allowBodyFallback: true, CreateTokenOptions());
        var context = sut.GetPrincipalContext(principal);

        context.TenantId.Should().Be(tenantId);
        context.UserId.Should().Be(userId);
        context.CurrentSessionId.Should().Be(sessionId);
        context.Email.Should().Be("user@norge360.test");
    }

    [Fact]
    public void GetPrincipalContext_Should_Throw_When_Claims_Are_Invalid()
    {
        var principal = new ClaimsPrincipal(new ClaimsIdentity(
        [
            new Claim("tenant_id", "invalid-guid"),
            new Claim(ClaimTypes.NameIdentifier, Guid.NewGuid().ToString("D")),
            new Claim(JwtRegisteredClaimNames.Sid, Guid.NewGuid().ToString("D"))
        ], "test"));

        var sut = CreateSut(null, allowBodyFallback: true, CreateTokenOptions());
        var action = () => sut.GetPrincipalContext(principal);

        var exception = action.Should().Throw<AuthApplicationException>().Which;
        exception.ErrorCode.Should().Be("invalid_principal_context");
        exception.StatusCode.Should().Be(StatusCodes.Status401Unauthorized);
    }

    private static AuthRequestContextAccessor CreateSut(
        TenantContext? tenantContext,
        bool allowBodyFallback,
        TokenTransportOptions tokenOptions)
    {
        var tenantAccessor = new Mock<ITenantContextAccessor>();
        tenantAccessor.SetupGet(x => x.Current).Returns(tenantContext);

        return new AuthRequestContextAccessor(
            tenantAccessor.Object,
            Options.Create(new TenantResolutionOptions { AllowBodyFallback = allowBodyFallback }),
            Options.Create(tokenOptions),
            new AuthCookieService(Options.Create(tokenOptions)));
    }

    private static TokenTransportOptions CreateTokenOptions(
        string mode = TokenTransportModes.CookiesOnly,
        bool allowRefreshTokenFromBody = false,
        bool allowSessionIdFromBody = false) =>
        new()
        {
            Mode = mode,
            AccessCookieName = "__Secure-auth-access",
            RefreshCookieName = "__Secure-auth-refresh",
            SessionCookieName = "__Secure-auth-session",
            AccessCookiePath = "/",
            RefreshCookiePath = "/api/auth",
            SessionCookiePath = "/api/auth",
            SameSite = "Lax",
            AllowRefreshTokenFromRequestBody = allowRefreshTokenFromBody,
            AllowSessionIdFromRequestBody = allowSessionIdFromBody
        };

    private static DefaultHttpContext CreateHttpContextWithCookies(params (string Name, string Value)[] cookies)
    {
        var context = new DefaultHttpContext();
        context.Request.Headers.Cookie = string.Join("; ", cookies.Select(c => $"{c.Name}={c.Value}"));
        return context;
    }
}
