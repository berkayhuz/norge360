// <copyright file="CookieOriginProtectionMiddlewareTests.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using FluentAssertions;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;
using Norge360.Auth.API.Cookies;
using Norge360.Auth.API.Middlewares;
using Norge360.Auth.API.Security;
using Norge360.Auth.Application.Options;

namespace Norge360.Auth.Api.FunctionalTests.Security;

public sealed class CookieOriginProtectionMiddlewareTests
{
    [Fact]
    public async Task InvokeAsync_Should_Bypass_For_Safe_Methods()
    {
        var (sut, context, nextCalled) = CreateSut(HttpMethods.Get, "/api/auth/logout");
        context.Request.Headers.Cookie = "__Secure-Norge360-access=abc";

        await sut.InvokeAsync(context);

        nextCalled().Should().BeTrue();
        context.Response.StatusCode.Should().Be(StatusCodes.Status200OK);
    }

    [Fact]
    public async Task InvokeAsync_Should_Bypass_For_Anonymous_Path_Prefixes()
    {
        var (sut, context, nextCalled) = CreateSut(HttpMethods.Post, "/health/live");
        context.Request.Headers.Cookie = "__Secure-Norge360-access=abc";

        await sut.InvokeAsync(context);

        nextCalled().Should().BeTrue();
    }

    [Fact]
    public async Task InvokeAsync_Should_Bypass_For_BodyOnly_Mode()
    {
        var (sut, context, nextCalled) = CreateSut(HttpMethods.Post, "/api/auth/logout", tokenMode: TokenTransportModes.BodyOnly);
        context.Request.Headers.Cookie = "__Secure-Norge360-access=abc";

        await sut.InvokeAsync(context);

        nextCalled().Should().BeTrue();
    }

    [Fact]
    public async Task InvokeAsync_Should_Bypass_When_Request_Does_Not_Carry_Auth_Cookies()
    {
        var (sut, context, nextCalled) = CreateSut(HttpMethods.Post, "/api/auth/logout");

        await sut.InvokeAsync(context);

        nextCalled().Should().BeTrue();
    }

    [Fact]
    public async Task InvokeAsync_Should_Reject_When_Auth_Cookie_Exists_And_Origin_Missing()
    {
        var (sut, context, nextCalled) = CreateSut(HttpMethods.Post, "/api/auth/logout");
        context.Request.Headers.Cookie = "__Secure-Norge360-access=abc";

        await sut.InvokeAsync(context);

        nextCalled().Should().BeFalse();
        context.Response.StatusCode.Should().Be(StatusCodes.Status403Forbidden);
    }

    [Fact]
    public async Task InvokeAsync_Should_Reject_When_Origin_Is_Not_Allowed()
    {
        var (sut, context, nextCalled) = CreateSut(HttpMethods.Post, "/api/auth/logout");
        context.Request.Headers.Cookie = "__Secure-Norge360-access=abc";
        context.Request.Headers.Origin = "https://evil.example";

        await sut.InvokeAsync(context);

        nextCalled().Should().BeFalse();
        context.Response.StatusCode.Should().Be(StatusCodes.Status403Forbidden);
    }

    [Fact]
    public async Task InvokeAsync_Should_Allow_When_Origin_Is_Allowed()
    {
        var (sut, context, nextCalled) = CreateSut(HttpMethods.Post, "/api/auth/logout");
        context.Request.Headers.Cookie = "__Secure-Norge360-access=abc";
        context.Request.Headers.Origin = "https://app.Norge360.com";

        await sut.InvokeAsync(context);

        nextCalled().Should().BeTrue();
    }

    [Fact]
    public async Task InvokeAsync_Should_Allow_When_Referer_Matches_Allowed_Origin_And_Origin_Header_Is_Missing()
    {
        var (sut, context, nextCalled) = CreateSut(HttpMethods.Post, "/api/auth/logout");
        context.Request.Headers.Cookie = "__Secure-Norge360-access=abc";
        context.Request.Headers.Referer = "https://app.Norge360.com/path/sub?x=1";

        await sut.InvokeAsync(context);

        nextCalled().Should().BeTrue();
    }

    private static (CookieOriginProtectionMiddleware Sut, DefaultHttpContext Context, Func<bool> NextCalled) CreateSut(
        string method,
        string path,
        string tokenMode = TokenTransportModes.CookiesOnly)
    {
        var nextCalled = false;
        var middleware = new CookieOriginProtectionMiddleware(
            _ =>
            {
                nextCalled = true;
                return Task.CompletedTask;
            },
            Options.Create(new ApiCorsOptions
            {
                AllowedOrigins = ["https://app.Norge360.com"]
            }),
            Options.Create(new TokenTransportOptions
            {
                Mode = tokenMode,
                AccessCookieName = "__Secure-Norge360-access",
                RefreshCookieName = "__Secure-Norge360-refresh",
                SessionCookieName = "__Secure-Norge360-session"
            }),
            new AuthCookieService(Options.Create(new TokenTransportOptions
            {
                Mode = tokenMode,
                AccessCookieName = "__Secure-Norge360-access",
                RefreshCookieName = "__Secure-Norge360-refresh",
                SessionCookieName = "__Secure-Norge360-session"
            })),
            NullLogger<CookieOriginProtectionMiddleware>.Instance);

        var context = new DefaultHttpContext();
        context.Request.Method = method;
        context.Request.Path = path;
        context.RequestServices = new ServiceCollection()
            .AddOptions()
            .AddProblemDetails()
            .BuildServiceProvider();

        return (middleware, context, () => nextCalled);
    }
}
