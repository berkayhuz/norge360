// <copyright file="AuthCookieServiceTests.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using FluentAssertions;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Options;
using Norge360.Auth.API.Cookies;
using Norge360.Auth.Application.Options;
using Norge360.Auth.Contracts.Responses;

namespace Norge360.Auth.Api.FunctionalTests.Security;

public sealed class AuthCookieServiceTests
{
    [Fact]
    public void ShouldReturnTokensInBody_Should_Be_True_For_BodyOnly_And_HybridDevelopment()
    {
        CreateSut(CreateOptions(TokenTransportModes.BodyOnly)).ShouldReturnTokensInBody.Should().BeTrue();
        CreateSut(CreateOptions(TokenTransportModes.HybridDevelopment)).ShouldReturnTokensInBody.Should().BeTrue();
    }

    [Fact]
    public void ShouldReturnTokensInBody_Should_Be_False_For_CookiesOnly()
    {
        CreateSut(CreateOptions(TokenTransportModes.CookiesOnly)).ShouldReturnTokensInBody.Should().BeFalse();
    }

    [Fact]
    public void CreateResponsePayload_Should_Return_TokenResponse_In_BodyOnly_Mode()
    {
        var response = CreateTokenResponse();
        var sut = CreateSut(CreateOptions(TokenTransportModes.BodyOnly));

        var payload = sut.CreateResponsePayload(response);

        payload.Should().BeOfType<AuthenticationTokenResponse>();
        payload.Should().Be(response);
    }

    [Fact]
    public void CreateResponsePayload_Should_Return_SessionResponse_In_CookiesOnly_Mode()
    {
        var response = CreateTokenResponse();
        var sut = CreateSut(CreateOptions(TokenTransportModes.CookiesOnly));

        var payload = sut.CreateResponsePayload(response);

        var sessionPayload = payload.Should().BeOfType<AuthIssuedSessionResponse>().Subject;
        sessionPayload.SessionId.Should().Be(response.SessionId);
        sessionPayload.TenantId.Should().Be(response.TenantId);
    }

    [Fact]
    public void Apply_Should_Not_Set_Cookies_In_BodyOnly_Mode()
    {
        var context = CreateHttpContext(isHttps: true);
        var sut = CreateSut(CreateOptions(TokenTransportModes.BodyOnly));

        sut.Apply(context.Response, CreateTokenResponse());

        context.Response.Headers.SetCookie.Should().BeEmpty();
    }

    [Fact]
    public void Apply_Should_Set_Access_Refresh_And_Session_Cookies_In_CookiesOnly_Mode()
    {
        var options = CreateOptions(TokenTransportModes.CookiesOnly);
        var context = CreateHttpContext(isHttps: true);
        var sut = CreateSut(options);
        var tokenResponse = CreateTokenResponse();

        sut.Apply(context.Response, tokenResponse);

        var cookies = context.Response.Headers.SetCookie.ToArray();
        cookies.Should().HaveCount(3);
        cookies.Should().Contain(item => item.Contains($"{options.AccessCookieName}={tokenResponse.AccessToken}", StringComparison.Ordinal));
        cookies.Should().Contain(item => item.Contains($"{options.RefreshCookieName}={tokenResponse.RefreshToken}", StringComparison.Ordinal));
        cookies.Should().Contain(item => item.Contains($"{options.SessionCookieName}={tokenResponse.SessionId:D}", StringComparison.Ordinal));
    }

    [Fact]
    public void Apply_Should_Set_Expires_For_Persistent_Sessions()
    {
        var context = CreateHttpContext(isHttps: true);
        var sut = CreateSut(CreateOptions(TokenTransportModes.CookiesOnly));
        var persistentTokenResponse = CreateTokenResponse(isPersistent: true);

        sut.Apply(context.Response, persistentTokenResponse);

        context.Response.Headers.SetCookie.ToArray()
            .Should().OnlyContain(item => item.Contains("expires=", StringComparison.OrdinalIgnoreCase));
    }

    [Fact]
    public void Apply_Should_Not_Set_Expires_For_NonPersistent_Sessions()
    {
        var context = CreateHttpContext(isHttps: true);
        var sut = CreateSut(CreateOptions(TokenTransportModes.CookiesOnly));
        var nonPersistentTokenResponse = CreateTokenResponse(isPersistent: false);

        sut.Apply(context.Response, nonPersistentTokenResponse);

        context.Response.Headers.SetCookie.ToArray()
            .Should().OnlyContain(item => !item.Contains("expires=", StringComparison.OrdinalIgnoreCase));
    }

    [Fact]
    public void Apply_Should_Respect_CookieDomain_For_NonHost_Cookies()
    {
        var options = CreateOptions(TokenTransportModes.CookiesOnly);
        options.CookieDomain = ".Norge360.com";
        options.AccessCookieName = "access";
        options.RefreshCookieName = "refresh";
        options.SessionCookieName = "session";

        var context = CreateHttpContext(isHttps: true);
        var sut = CreateSut(options);

        sut.Apply(context.Response, CreateTokenResponse());

        context.Response.Headers.SetCookie.ToArray()
            .Should().OnlyContain(item => item.Contains("domain=.Norge360.com", StringComparison.OrdinalIgnoreCase));
    }

    [Fact]
    public void Apply_Should_Ignore_CookieDomain_For_Host_Prefixed_Cookies()
    {
        var options = CreateOptions(TokenTransportModes.CookiesOnly);
        options.CookieDomain = ".Norge360.com";
        options.AccessCookieName = "__Host-access";
        options.RefreshCookieName = "__Host-refresh";
        options.SessionCookieName = "__Host-session";

        var context = CreateHttpContext(isHttps: true);
        var sut = CreateSut(options);

        sut.Apply(context.Response, CreateTokenResponse());

        context.Response.Headers.SetCookie.ToArray()
            .Should().OnlyContain(item => !item.Contains("domain=", StringComparison.OrdinalIgnoreCase));
    }

    [Fact]
    public void Clear_Should_Delete_All_Cookies()
    {
        var options = CreateOptions(TokenTransportModes.CookiesOnly);
        var context = CreateHttpContext(isHttps: true);
        var sut = CreateSut(options);

        sut.Clear(context.Response);

        var cookies = context.Response.Headers.SetCookie.ToArray();
        cookies.Should().HaveCount(3);
        cookies.Should().Contain(item => item.Contains($"{options.AccessCookieName}=", StringComparison.Ordinal));
        cookies.Should().Contain(item => item.Contains("expires=Thu, 01 Jan 1970", StringComparison.OrdinalIgnoreCase));
    }

    [Fact]
    public void Apply_Should_Force_Secure_For_SecurePrefixed_Cookies_Even_On_NonHttps()
    {
        var options = CreateOptions(TokenTransportModes.CookiesOnly);
        options.AccessCookieName = "__Secure-access";

        var context = CreateHttpContext(isHttps: false);
        var sut = CreateSut(options);

        sut.Apply(context.Response, CreateTokenResponse());

        context.Response.Headers.SetCookie.ToArray()
            .Should().Contain(item => item.StartsWith($"{options.AccessCookieName}=", StringComparison.Ordinal) &&
                                      item.Contains("secure", StringComparison.OrdinalIgnoreCase));
    }

    [Fact]
    public void Apply_Should_Force_Secure_And_Omit_Domain_For_HostPrefixed_Cookies()
    {
        var options = CreateOptions(TokenTransportModes.CookiesOnly);
        options.CookieDomain = ".Norge360.com";
        options.AccessCookieName = "__Host-access";
        options.RefreshCookieName = "__Host-refresh";
        options.SessionCookieName = "__Host-session";
        options.AccessCookiePath = "/";
        options.RefreshCookiePath = "/";
        options.SessionCookiePath = "/";

        var context = CreateHttpContext(isHttps: false);
        var sut = CreateSut(options);

        sut.Apply(context.Response, CreateTokenResponse());

        context.Response.Headers.SetCookie.ToArray()
            .Should().OnlyContain(item =>
                item.Contains("secure", StringComparison.OrdinalIgnoreCase) &&
                item.Contains("path=/", StringComparison.OrdinalIgnoreCase) &&
                !item.Contains("domain=", StringComparison.OrdinalIgnoreCase));
    }

    private static AuthenticationTokenResponse CreateTokenResponse(bool isPersistent = false) =>
        new(
            "access-token",
            DateTime.UtcNow.AddMinutes(15),
            "refresh-token",
            DateTime.UtcNow.AddDays(14),
            Guid.NewGuid(),
            Guid.NewGuid(),
            "berkay",
            "berkay@example.com",
            Guid.NewGuid(),
            isPersistent);

    private static AuthCookieService CreateSut(TokenTransportOptions options) =>
        new(Options.Create(options));

    private static DefaultHttpContext CreateHttpContext(bool isHttps)
    {
        var context = new DefaultHttpContext();
        context.Request.Scheme = isHttps ? "https" : "http";
        return context;
    }

    private static TokenTransportOptions CreateOptions(string mode) =>
        new()
        {
            Mode = mode,
            AccessCookieName = "__Secure-Norge360-access",
            RefreshCookieName = "__Secure-Norge360-refresh",
            SessionCookieName = "__Secure-Norge360-session",
            SameSite = "Lax",
            AccessCookiePath = "/",
            RefreshCookiePath = "/api/auth",
            SessionCookiePath = "/api/auth"
        };
}
