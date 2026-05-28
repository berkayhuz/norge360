// <copyright file="SecurityHeadersMiddlewareBenchmarks.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using BenchmarkDotNet.Attributes;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Options;
using Norge360.Auth.API.Middlewares;
using Norge360.Auth.API.Security;

namespace Norge360.Auth.Benchmarks;

[MemoryDiagnoser]
public class SecurityHeadersMiddlewareBenchmarks
{
    private SecurityHeadersMiddleware _middleware = default!;
    private DefaultHttpContext _httpContext = default!;
    private DefaultHttpContext _httpsContext = default!;

    [GlobalSetup]
    public void Setup()
    {
        _middleware = new SecurityHeadersMiddleware(
            _ => Task.CompletedTask,
            Options.Create(new ApiSecurityHeadersOptions()));

        _httpContext = new DefaultHttpContext();
        _httpContext.Request.Scheme = "http";
        _httpsContext = new DefaultHttpContext();
        _httpsContext.Request.Scheme = "https";
    }

    [Benchmark]
    public Task Apply_On_Http() => _middleware.InvokeAsync(_httpContext);

    [Benchmark]
    public Task Apply_On_Https() => _middleware.InvokeAsync(_httpsContext);
}
