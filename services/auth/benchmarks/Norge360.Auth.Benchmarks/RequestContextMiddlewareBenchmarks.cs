// <copyright file="RequestContextMiddlewareBenchmarks.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using BenchmarkDotNet.Attributes;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Logging.Abstractions;
using Norge360.Auth.API.Middlewares;

namespace Norge360.Auth.Benchmarks;

[MemoryDiagnoser]
public class RequestContextMiddlewareBenchmarks
{
    private RequestContextMiddleware _middleware = default!;
    private HttpContext _context = default!;

    [GlobalSetup]
    public void Setup()
    {
        _middleware = new RequestContextMiddleware(
            async ctx => { await ctx.Response.WriteAsync("ok"); },
            NullLogger<RequestContextMiddleware>.Instance);
        _context = new DefaultHttpContext();
    }

    [Benchmark]
    public Task Invoke_With_ResponseWrite() => _middleware.InvokeAsync(_context);
}
