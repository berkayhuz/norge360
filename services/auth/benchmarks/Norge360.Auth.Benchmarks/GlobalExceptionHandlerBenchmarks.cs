// <copyright file="GlobalExceptionHandlerBenchmarks.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using BenchmarkDotNet.Attributes;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging.Abstractions;
using Norge360.Auth.API.Exceptions;
using Norge360.Auth.Application.Exceptions;

namespace Norge360.Auth.Benchmarks;

[MemoryDiagnoser]
public class GlobalExceptionHandlerBenchmarks
{
    private GlobalExceptionHandler _handler = default!;
    private HttpContext _context = default!;
    private Exception _genericException = default!;
    private AuthApplicationException _authException = default!;

    [GlobalSetup]
    public void Setup()
    {
        _handler = new GlobalExceptionHandler(NullLogger<GlobalExceptionHandler>.Instance);
        _context = new DefaultHttpContext
        {
            RequestServices = new Microsoft.Extensions.DependencyInjection.ServiceCollection()
                .AddSingleton<IProblemDetailsService, BenchmarkProblemDetailsService>()
                .BuildServiceProvider()
        };
        _context.Request.Path = "/api/auth/test";
        _genericException = new InvalidOperationException("boom");
        _authException = new AuthApplicationException(
            "Forbidden",
            "not allowed",
            StatusCodes.Status403Forbidden,
            errorCode: "forbidden_operation");
    }

    [Benchmark]
    public ValueTask<bool> Handle_AuthApplicationException() =>
        _handler.TryHandleAsync(_context, _authException, CancellationToken.None);

    [Benchmark]
    public ValueTask<bool> Handle_UnknownException() =>
        _handler.TryHandleAsync(_context, _genericException, CancellationToken.None);

    private sealed class BenchmarkProblemDetailsService : IProblemDetailsService
    {
        public ValueTask<bool> TryWriteAsync(ProblemDetailsContext context) => ValueTask.FromResult(true);
        public ValueTask WriteAsync(ProblemDetailsContext context) => ValueTask.CompletedTask;
    }
}
