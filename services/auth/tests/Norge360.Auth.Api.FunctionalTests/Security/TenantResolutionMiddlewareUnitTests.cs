// <copyright file="TenantResolutionMiddlewareUnitTests.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using FluentAssertions;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;
using Norge360.Auth.API.Middlewares;
using Norge360.Auth.Application.Abstractions;
using Norge360.Auth.Application.Options;
using Norge360.Auth.Domain.Entities;

namespace Norge360.Auth.Api.FunctionalTests.Security;

public sealed class TenantResolutionMiddlewareUnitTests
{
    [Fact]
    public async Task InvokeAsync_Should_Resolve_From_TenantId_Header_For_Trusted_Request()
    {
        var tenantId = Guid.NewGuid();
        var (sut, nextCalled) = CreateSut();
        var context = CreateContext("/api/auth/workspaces", trusted: true);
        context.Request.Headers["X-Tenant-Id"] = tenantId.ToString("D");

        await sut.InvokeAsync(context, new StaticTenantRepository());

        nextCalled().Should().BeTrue();
        var tenantContext = TenantResolutionMiddleware.GetTenantContext(context);
        tenantContext.Should().NotBeNull();
        tenantContext!.TenantId.Should().Be(tenantId);
        tenantContext.Source.Should().Be("header");
    }

    [Fact]
    public async Task InvokeAsync_Should_Resolve_From_Slug_Header_Using_Repository()
    {
        var resolvedId = Guid.NewGuid();
        var (sut, nextCalled) = CreateSut();
        var context = CreateContext("/api/auth/workspaces", trusted: true);
        context.Request.Headers["X-Tenant-Slug"] = "acme";

        await sut.InvokeAsync(context, new StaticTenantRepository(new Tenant { Id = resolvedId, Slug = "acme", Name = "Acme", CreatedAt = DateTime.UtcNow }));

        nextCalled().Should().BeTrue();
        var tenantContext = TenantResolutionMiddleware.GetTenantContext(context);
        tenantContext.Should().NotBeNull();
        tenantContext!.TenantId.Should().Be(resolvedId);
        tenantContext.TenantSlug.Should().Be("acme");
        tenantContext.Source.Should().Be("slug-header");
    }

    [Fact]
    public async Task InvokeAsync_Should_Resolve_From_Host_Subdomain_Using_Repository()
    {
        var resolvedId = Guid.NewGuid();
        var (sut, nextCalled) = CreateSut();
        var context = CreateContext("/api/auth/workspaces", trusted: true);
        context.Request.Host = new HostString("northwind.Norge360.com");

        await sut.InvokeAsync(context, new StaticTenantRepository(new Tenant { Id = resolvedId, Slug = "northwind", Name = "Northwind", CreatedAt = DateTime.UtcNow }));

        nextCalled().Should().BeTrue();
        var tenantContext = TenantResolutionMiddleware.GetTenantContext(context);
        tenantContext.Should().NotBeNull();
        tenantContext!.TenantId.Should().Be(resolvedId);
        tenantContext.TenantSlug.Should().Be("northwind");
        tenantContext.Source.Should().Be("host");
    }

    [Fact]
    public async Task InvokeAsync_Should_Bypass_When_Path_Is_Tenant_Optional()
    {
        var (sut, nextCalled) = CreateSut();
        var context = CreateContext("/api/auth/register", trusted: false);

        await sut.InvokeAsync(context, new StaticTenantRepository());

        nextCalled().Should().BeTrue();
        TenantResolutionMiddleware.GetTenantContext(context).Should().BeNull();
    }

    [Fact]
    public async Task InvokeAsync_Should_Return_BadRequest_When_Resolution_Required_And_Unresolved()
    {
        var (sut, nextCalled) = CreateSut();
        var context = CreateContext("/api/auth/workspaces", trusted: false);

        await sut.InvokeAsync(context, new StaticTenantRepository());

        nextCalled().Should().BeFalse();
        context.Response.StatusCode.Should().Be(StatusCodes.Status400BadRequest);
    }

    private static (TenantResolutionMiddleware Sut, Func<bool> NextCalled) CreateSut()
    {
        var nextCalled = false;
        var options = Options.Create(new TenantResolutionOptions
        {
            HeaderName = "X-Tenant-Id",
            SlugHeaderName = "X-Tenant-Slug",
            RequireResolvedTenant = true,
            AllowBodyFallback = false,
            TrustedHostSuffixes = [".Norge360.com"],
            TenantOptionalPathPrefixes = ["/api/auth/register"]
        });

        var middleware = new TenantResolutionMiddleware(
            _ =>
            {
                nextCalled = true;
                return Task.CompletedTask;
            },
            options,
            NullLogger<TenantResolutionMiddleware>.Instance);

        return (middleware, () => nextCalled);
    }

    private static DefaultHttpContext CreateContext(string path, bool trusted)
    {
        var context = new DefaultHttpContext();
        context.Request.Method = HttpMethods.Get;
        context.Request.Path = path;
        context.RequestServices = new ServiceCollection()
            .AddOptions()
            .AddProblemDetails()
            .BuildServiceProvider();

        if (trusted)
        {
            context.Items[TrustedGatewayMiddleware.TrustedGatewayValidatedItemName] = true;
        }

        return context;
    }

    private sealed class StaticTenantRepository(Tenant? tenant = null) : ITenantRepository
    {
        public Task<Tenant?> GetByIdAsync(Guid tenantId, CancellationToken cancellationToken) =>
            Task.FromResult<Tenant?>(null);

        public Task<Tenant?> GetBySlugAsync(string slug, CancellationToken cancellationToken) =>
            Task.FromResult<Tenant?>(tenant is null
                ? null
                : new Tenant
                {
                    Id = tenant.Id,
                    Name = tenant.Name,
                    Slug = slug,
                    CreatedAt = tenant.CreatedAt,
                    UpdatedAt = tenant.UpdatedAt,
                    IsActive = tenant.IsActive
                });

        public Task AddAsync(Tenant tenant, CancellationToken cancellationToken) => Task.CompletedTask;

        public Task DeactivateAsync(Tenant tenant, DateTime utcNow, Guid actorUserId, CancellationToken cancellationToken) => Task.CompletedTask;
    }
}
