// <copyright file="TrustedGatewayMiddlewareBenchmarks.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using BenchmarkDotNet.Attributes;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;
using Norge360.AspNetCore.TrustedGateway.Abstractions;
using Norge360.AspNetCore.TrustedGateway.Models;
using Norge360.AspNetCore.TrustedGateway.Options;
using Norge360.Auth.API.Middlewares;
using Norge360.Auth.Application.Abstractions;
using Norge360.Auth.Application.Records;

namespace Norge360.Auth.Benchmarks;

[MemoryDiagnoser]
public class TrustedGatewayMiddlewareBenchmarks
{
    private TrustedGatewayMiddleware _successMiddleware = default!;
    private TrustedGatewayMiddleware _failureMiddleware = default!;
    private HttpContext _successContext = default!;
    private HttpContext _failureContext = default!;

    [GlobalSetup]
    public void Setup()
    {
        var options = Options.Create(new TrustedGatewayOptions
        {
            RequireTrustedGateway = true
        });

        _successMiddleware = new TrustedGatewayMiddleware(
            _ => Task.CompletedTask,
            options,
            new StaticValidator(TrustedGatewayValidationResult.Success()),
            new NoopSecurityAlertPublisher(),
            NullLogger<TrustedGatewayMiddleware>.Instance);

        _failureMiddleware = new TrustedGatewayMiddleware(
            _ => Task.CompletedTask,
            options,
            new StaticValidator(TrustedGatewayValidationResult.Fail(TrustedGatewayFailureReason.InvalidSource, "trusted_gateway_invalid_source")),
            new NoopSecurityAlertPublisher(),
            NullLogger<TrustedGatewayMiddleware>.Instance);

        _successContext = CreateContext("/api/v1/internal/identity/users/00000000-0000-0000-0000-000000000001/security-summary");
        _failureContext = CreateContext("/api/v1/internal/identity/users/00000000-0000-0000-0000-000000000001/security-summary");
    }

    [Benchmark]
    public Task Allow_When_TrustedGatewayValidator_Succeeds() => _successMiddleware.InvokeAsync(_successContext);

    [Benchmark]
    public Task Reject_When_TrustedGatewayValidator_Fails() => _failureMiddleware.InvokeAsync(_failureContext);

    private static HttpContext CreateContext(string path)
    {
        var context = new DefaultHttpContext();
        context.Request.Method = HttpMethods.Get;
        context.Request.Path = path;
        context.RequestServices = new ServiceCollection()
            .AddOptions()
            .AddProblemDetails()
            .BuildServiceProvider();
        return context;
    }

    private sealed class StaticValidator(TrustedGatewayValidationResult result) : ITrustedGatewayRequestValidator
    {
        public Task<TrustedGatewayValidationResult> ValidateAsync(HttpContext context, string correlationId, CancellationToken cancellationToken) =>
            Task.FromResult(result);
    }

    private sealed class NoopSecurityAlertPublisher : ISecurityAlertPublisher
    {
        public Task PublishAsync(SecurityAlert alert, CancellationToken cancellationToken = default) => Task.CompletedTask;
    }
}
