// <copyright file="AuthorizationCoreBenchmarks.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using BenchmarkDotNet.Attributes;
using Norge360.Authorization;

namespace Norge360.AspNetCore.Benchmarks;

[MemoryDiagnoser]
public class AuthorizationCoreBenchmarks
{
    private List<RowItem> _items = null!;
    private AuthorizationScope _scope = null!;

    [GlobalSetup]
    public void Setup()
    {
        var tenantId = Guid.Parse("d2501385-53f6-483f-a17f-8c1bc37da6ea");
        var userId = Guid.Parse("4b75f7f4-c7e6-4d48-b8a4-c838c6fd4ec2");

        _scope = new AuthorizationScope(
            tenantId,
            userId,
            "orders",
            RowAccessLevel.Assigned,
            ["orders.read"]);

        _items =
        [
            new RowItem(tenantId, userId, null),
            new RowItem(tenantId, null, userId),
            new RowItem(tenantId, Guid.NewGuid(), Guid.NewGuid()),
            new RowItem(Guid.NewGuid(), userId, userId)
        ];
    }

    [Benchmark]
    public int ApplyRowScope_Count()
    {
        return _items
            .AsQueryable()
            .ApplyRowScope(
                _scope,
                x => x.TenantId,
                x => x.OwnerUserId,
                x => x.AssignedUserId)
            .Count();
    }

    private sealed record RowItem(Guid TenantId, Guid? OwnerUserId, Guid? AssignedUserId);
}
