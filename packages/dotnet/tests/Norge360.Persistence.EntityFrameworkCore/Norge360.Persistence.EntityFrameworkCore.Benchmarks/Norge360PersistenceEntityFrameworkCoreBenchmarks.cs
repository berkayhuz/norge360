// <copyright file="Norge360PersistenceEntityFrameworkCoreBenchmarks.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using BenchmarkDotNet.Attributes;

namespace Norge360.Persistence.EntityFrameworkCore.Benchmarks;

[MemoryDiagnoser]
public class Norge360PersistenceEntityFrameworkCoreBenchmarks
{
    [Benchmark(Baseline = true)]
    public bool CanResolveModelBuilderExtensionsType() => typeof(global::Norge360.Persistence.EntityFrameworkCore.ModelBuilderExtensions).IsAbstract;
}