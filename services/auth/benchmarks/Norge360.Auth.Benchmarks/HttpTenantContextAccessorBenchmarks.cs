// <copyright file="HttpTenantContextAccessorBenchmarks.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using BenchmarkDotNet.Attributes;
using Microsoft.AspNetCore.Http;
using Norge360.Auth.API.Accessors;
using Norge360.Auth.Application.Records;

namespace Norge360.Auth.Benchmarks;

[MemoryDiagnoser]
public class HttpTenantContextAccessorBenchmarks
{
    private HttpTenantContextAccessor _withTenantAccessor = default!;
    private HttpTenantContextAccessor _withoutTenantAccessor = default!;

    [GlobalSetup]
    public void Setup()
    {
        var withTenantContext = new DefaultHttpContext();
        withTenantContext.Items["TenantContext"] = new TenantContext(Guid.NewGuid(), "acme", "host", true);

        var withoutTenantContext = new DefaultHttpContext();

        _withTenantAccessor = new HttpTenantContextAccessor(new HttpContextAccessor { HttpContext = withTenantContext });
        _withoutTenantAccessor = new HttpTenantContextAccessor(new HttpContextAccessor { HttpContext = withoutTenantContext });
    }

    [Benchmark]
    public TenantContext? Get_Current_With_Tenant() => _withTenantAccessor.Current;

    [Benchmark]
    public TenantContext? Get_Current_Without_Tenant() => _withoutTenantAccessor.Current;
}
