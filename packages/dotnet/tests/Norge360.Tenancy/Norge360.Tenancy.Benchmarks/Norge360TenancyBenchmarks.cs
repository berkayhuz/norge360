// <copyright file="Norge360TenancyBenchmarks.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using BenchmarkDotNet.Attributes;

namespace Norge360.Tenancy.Benchmarks;

[MemoryDiagnoser]
public class Norge360TenancyBenchmarks
{
    [Benchmark(Baseline = true)]
    public bool CanResolveTenantContextExtensionsType() => typeof(global::Norge360.Tenancy.TenantContextExtensions).IsAbstract;
}