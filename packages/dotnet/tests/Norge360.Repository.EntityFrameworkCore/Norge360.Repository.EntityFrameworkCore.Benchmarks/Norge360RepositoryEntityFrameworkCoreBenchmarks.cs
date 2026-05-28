// <copyright file="Norge360RepositoryEntityFrameworkCoreBenchmarks.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using BenchmarkDotNet.Attributes;

namespace Norge360.Repository.EntityFrameworkCore.Benchmarks;

[MemoryDiagnoser]
public class Norge360RepositoryEntityFrameworkCoreBenchmarks
{
    [Benchmark(Baseline = true)]
    public bool CanResolveEfRepositoryType() => typeof(global::Norge360.Repository.EntityFrameworkCore.EfRepository<object, object>).IsSealed;
}