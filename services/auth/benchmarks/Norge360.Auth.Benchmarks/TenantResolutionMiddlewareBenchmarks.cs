// <copyright file="TenantResolutionMiddlewareBenchmarks.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using BenchmarkDotNet.Attributes;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;
using Norge360.Auth.API.Middlewares;
using Norge360.Auth.Application.Abstractions;
using Norge360.Auth.Application.Options;
using Norge360.Auth.Domain.Entities;

namespace Norge360.Auth.Benchmarks;

[MemoryDiagnoser]
public class TenantResolutionMiddlewareBenchmarks
{
    private TenantResolutionMiddleware _headerResolutionMiddleware = default!;
    private TenantResolutionMiddleware _slugResolutionMiddleware = default!;
    private HttpContext _headerContext = default!;
    private HttpContext _slugContext = default!;
    private ITenantRepository _tenantRepository = default!;

    [GlobalSetup]
    public void Setup()
    {
        _headerResolutionMiddleware = new TenantResolutionMiddleware(
            _ => Task.CompletedTask,
            Options.Create(new TenantResolutionOptions
            {
                HeaderName = "X-Tenant-Id",
                SlugHeaderName = "X-Tenant-Slug",
                RequireResolvedTenant = true,
                AllowBodyFallback = false,
                TrustedHostSuffixes = [".Norge360.com"]
            }),
            NullLogger<TenantResolutionMiddleware>.Instance);

        _slugResolutionMiddleware = new TenantResolutionMiddleware(
            _ => Task.CompletedTask,
            Options.Create(new TenantResolutionOptions
            {
                HeaderName = "X-Tenant-Id",
                SlugHeaderName = "X-Tenant-Slug",
                RequireResolvedTenant = true,
                AllowBodyFallback = false,
                TrustedHostSuffixes = [".Norge360.com"]
            }),
            NullLogger<TenantResolutionMiddleware>.Instance);

        _headerContext = CreateTrustedContext("/api/v1/internal/membership/users/00000000-0000-0000-0000-000000000001/organizations");
        _headerContext.Request.Headers["X-Tenant-Id"] = Guid.NewGuid().ToString("D");

        _slugContext = CreateTrustedContext("/api/v1/internal/membership/users/00000000-0000-0000-0000-000000000001/organizations");
        _slugContext.Request.Headers["X-Tenant-Slug"] = "acme";

        _tenantRepository = new StaticTenantRepository();
    }

    [Benchmark]
    public Task Resolve_From_TenantId_Header() => _headerResolutionMiddleware.InvokeAsync(_headerContext, _tenantRepository);

    [Benchmark]
    public Task Resolve_From_Slug_Header_Using_Repository() => _slugResolutionMiddleware.InvokeAsync(_slugContext, _tenantRepository);

    private static HttpContext CreateTrustedContext(string path)
    {
        var context = new DefaultHttpContext();
        context.Request.Method = HttpMethods.Get;
        context.Request.Path = path;
        context.Items[TrustedGatewayMiddleware.TrustedGatewayValidatedItemName] = true;
        context.RequestServices = new ServiceCollection()
            .AddProblemDetails()
            .BuildServiceProvider();
        return context;
    }

    private sealed class StaticTenantRepository : ITenantRepository
    {
        public Task<Tenant?> GetByIdAsync(Guid id, CancellationToken cancellationToken = default) =>
            Task.FromResult<Tenant?>(null);

        public Task<Tenant?> GetBySlugAsync(string slug, CancellationToken cancellationToken = default) =>
            Task.FromResult<Tenant?>(new Tenant
            {
                Id = Guid.NewGuid(),
                Slug = slug,
                Name = "Acme",
                CreatedAt = DateTime.UtcNow,
                UpdatedAt = DateTime.UtcNow
            });

        public Task AddAsync(Tenant tenant, CancellationToken cancellationToken = default) => Task.CompletedTask;

        public Task DeactivateAsync(Tenant tenant, DateTime utcNow, Guid actorUserId, CancellationToken cancellationToken = default) =>
            Task.CompletedTask;
    }
}
