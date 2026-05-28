// <copyright file="Norge360.GuardsBenchmarks.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using BenchmarkDotNet.Attributes;

namespace Norge360.Guards.Benchmarks;

[MemoryDiagnoser]
public class Norge360GuardsBenchmarks
{
    [Benchmark(Baseline = true)]
    public string AgainstNullOrWhiteSpace_Valid() => Guard.AgainstNullOrWhiteSpace("  norge360  ", "value");

    [Benchmark]
    public Guid AgainstEmpty_Valid() => Guard.AgainstEmpty(Guid.NewGuid(), "id");

    [Benchmark]
    public object AgainstNull_Valid() => Guard.AgainstNull(new object(), "obj");
}
