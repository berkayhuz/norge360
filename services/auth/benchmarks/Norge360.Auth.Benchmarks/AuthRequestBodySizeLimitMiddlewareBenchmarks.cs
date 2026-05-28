// <copyright file="AuthRequestBodySizeLimitMiddlewareBenchmarks.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using BenchmarkDotNet.Attributes;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.DependencyInjection;
using Norge360.Auth.API.Middlewares;
using Norge360.Auth.API.Security;

namespace Norge360.Auth.Benchmarks;

[MemoryDiagnoser]
public class AuthRequestBodySizeLimitMiddlewareBenchmarks
{
    private AuthRequestBodySizeLimitMiddleware _middleware = default!;
    private HttpContext _allowContext = default!;
    private HttpContext _rejectContext = default!;

    [GlobalSetup]
    public void Setup()
    {
        _middleware = new AuthRequestBodySizeLimitMiddleware(_ => Task.CompletedTask);
        _allowContext = CreateContext(AuthRequestSizeLimits.AuthBodyBytes);
        _rejectContext = CreateContext(AuthRequestSizeLimits.AuthBodyBytes + 1);
    }

    [Benchmark]
    public Task Allow_When_ContentLength_Within_Limit() => _middleware.InvokeAsync(_allowContext);

    [Benchmark]
    public Task Reject_When_ContentLength_Exceeds_Limit() => _middleware.InvokeAsync(_rejectContext);

    private static HttpContext CreateContext(long contentLength)
    {
        var context = new DefaultHttpContext();
        context.Request.Method = HttpMethods.Post;
        context.Request.Path = "/api/auth/login";
        context.Request.ContentLength = contentLength;
        context.RequestServices = new ServiceCollection()
            .AddOptions()
            .AddProblemDetails()
            .BuildServiceProvider();
        return context;
    }
}
