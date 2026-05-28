// <copyright file="SecurityHeadersMiddlewareTests.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using FluentAssertions;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Options;
using Norge360.Auth.API.Middlewares;
using Norge360.Auth.API.Security;

namespace Norge360.Auth.Api.FunctionalTests.Security;

public sealed class SecurityHeadersMiddlewareTests
{
    [Fact]
    public async Task InvokeAsync_Should_Apply_Expected_Security_Headers_On_Https()
    {
        var context = new DefaultHttpContext();
        context.Request.Scheme = "https";

        var options = Options.Create(new ApiSecurityHeadersOptions
        {
            ContentSecurityPolicy = "default-src 'none'",
            ReferrerPolicy = "no-referrer",
            PermissionsPolicy = "camera=()",
            EnableHsts = true,
            HstsMaxAgeSeconds = 31536000,
            IncludeSubDomains = true,
            PreloadHsts = true
        });

        var sut = new SecurityHeadersMiddleware(_ => Task.CompletedTask, options);

        await sut.InvokeAsync(context);

        context.Response.Headers["Content-Security-Policy"].ToString().Should().Be("default-src 'none'");
        context.Response.Headers["Referrer-Policy"].ToString().Should().Be("no-referrer");
        context.Response.Headers["Permissions-Policy"].ToString().Should().Be("camera=()");
        context.Response.Headers["X-Content-Type-Options"].ToString().Should().Be("nosniff");
        context.Response.Headers["X-Frame-Options"].ToString().Should().Be("DENY");
        context.Response.Headers["Strict-Transport-Security"].ToString().Should().Contain("max-age=31536000");
    }

    [Fact]
    public async Task InvokeAsync_Should_Not_Set_Hsts_On_Http()
    {
        var context = new DefaultHttpContext();
        context.Request.Scheme = "http";
        var sut = new SecurityHeadersMiddleware(
            _ => Task.CompletedTask,
            Options.Create(new ApiSecurityHeadersOptions { EnableHsts = true }));

        await sut.InvokeAsync(context);

        context.Response.Headers.ContainsKey("Strict-Transport-Security").Should().BeFalse();
    }

    [Fact]
    public async Task InvokeAsync_Should_Set_NoStore_Cache_Headers()
    {
        var context = new DefaultHttpContext();
        var sut = new SecurityHeadersMiddleware(
            _ => Task.CompletedTask,
            Options.Create(new ApiSecurityHeadersOptions()));

        await sut.InvokeAsync(context);

        context.Response.Headers["Cache-Control"].ToString().Should().Be("no-store");
        context.Response.Headers["Pragma"].ToString().Should().Be("no-cache");
    }
}
