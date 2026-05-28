// <copyright file="Norge360PersistenceEntityFrameworkCoreSoftDeleteBenchmarks.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using BenchmarkDotNet.Attributes;

namespace Norge360.Persistence.EntityFrameworkCore.SoftDelete.Benchmarks;

[MemoryDiagnoser]
public class Norge360PersistenceEntityFrameworkCoreSoftDeleteBenchmarks
{
    [Benchmark(Baseline = true)]
    public object CreateInterceptor() => new global::Norge360.Persistence.EntityFrameworkCore.SoftDelete.SoftDeleteSaveChangesInterceptor();
}