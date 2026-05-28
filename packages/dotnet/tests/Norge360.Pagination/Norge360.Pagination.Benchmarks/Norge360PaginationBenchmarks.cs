// <copyright file="Norge360PaginationBenchmarks.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>
using BenchmarkDotNet.Attributes;

namespace Norge360.Pagination.Benchmarks;

[MemoryDiagnoser]
public class Norge360PaginationBenchmarks
{
    private static readonly IReadOnlyList<int> Items = Enumerable.Range(1, 20).ToArray();

    [Benchmark(Baseline = true)]
    public int NormalizeRequest()
    {
        var request = global::Norge360.Pagination.PageRequest.Normalize(3, 25);
        return request.Skip;
    }

    [Benchmark]
    public int CreatePagedResult()
    {
        var result = global::Norge360.Pagination.PagedResult<int>.Create(
            Items,
            500,
            global::Norge360.Pagination.PageRequest.Normalize(3, 20));
        return result.TotalPages;
    }
}
