// <copyright file="CookieOriginProtectionMiddlewareBenchmarks.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using BenchmarkDotNet.Attributes;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;
using Norge360.Auth.API.Cookies;
using Norge360.Auth.API.Middlewares;
using Norge360.Auth.API.Security;
using Norge360.Auth.Application.Options;

namespace Norge360.Auth.Benchmarks;

[MemoryDiagnoser]
public class CookieOriginProtectionMiddlewareBenchmarks
{
    private CookieOriginProtectionMiddleware _allowMiddleware = default!;
    private CookieOriginProtectionMiddleware _denyMiddleware = default!;
    private HttpContext _allowContext = default!;
    private HttpContext _denyContext = default!;

    [GlobalSetup]
    public void Setup()
    {
        _allowMiddleware = CreateMiddleware();
        _denyMiddleware = CreateMiddleware();

        _allowContext = CreateContext(origin: "https://app.Norge360.com");
        _denyContext = CreateContext(origin: "https://evil.example");
    }

    [Benchmark]
    public Task Allow_UnsafeCookieRequest_With_AllowedOrigin() => _allowMiddleware.InvokeAsync(_allowContext);

    [Benchmark]
    public Task Reject_UnsafeCookieRequest_With_DisallowedOrigin() => _denyMiddleware.InvokeAsync(_denyContext);

    private static CookieOriginProtectionMiddleware CreateMiddleware()
    {
        var tokenOptions = new TokenTransportOptions
        {
            Mode = TokenTransportModes.CookiesOnly,
            AccessCookieName = "__Secure-Norge360-access",
            RefreshCookieName = "__Secure-Norge360-refresh",
            SessionCookieName = "__Secure-Norge360-session"
        };

        return new CookieOriginProtectionMiddleware(
            _ => Task.CompletedTask,
            Options.Create(new ApiCorsOptions
            {
                AllowedOrigins = ["https://app.Norge360.com"]
            }),
            Options.Create(tokenOptions),
            new AuthCookieService(Options.Create(tokenOptions)),
            NullLogger<CookieOriginProtectionMiddleware>.Instance);
    }

    private static HttpContext CreateContext(string origin)
    {
        var context = new DefaultHttpContext();
        context.Request.Method = HttpMethods.Post;
        context.Request.Path = "/api/auth/logout";
        context.Request.Headers.Origin = origin;
        context.Request.Headers.Cookie = "__Secure-Norge360-access=abc";
        context.RequestServices = new ServiceCollection()
            .AddOptions()
            .AddProblemDetails()
            .BuildServiceProvider();
        return context;
    }
}
