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
        var userId = Guid.Parse("4b75f7f4-c7e6-4d48-b8a4-c838c6fd4ec2");

        _scope = new AuthorizationScope(
            userId,
            "orders",
            RowAccessLevel.Assigned,
            ["orders.read"]);

        _items =
        [
            new RowItem(userId, null),
            new RowItem(null, userId),
            new RowItem(Guid.NewGuid(), Guid.NewGuid()),
            new RowItem(null, null)
        ];
    }

    [Benchmark]
    public int ApplyRowScope_Count()
    {
        return _items
            .AsQueryable()
            .ApplyRowScope(
                _scope,
                x => x.OwnerUserId,
                x => x.AssignedUserId)
            .Count();
    }

    private sealed record RowItem(Guid? OwnerUserId, Guid? AssignedUserId);
}
