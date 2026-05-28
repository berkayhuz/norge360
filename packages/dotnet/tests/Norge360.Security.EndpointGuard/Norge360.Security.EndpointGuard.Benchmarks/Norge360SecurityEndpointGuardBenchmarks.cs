// <copyright file="Norge360SecurityEndpointGuardBenchmarks.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using BenchmarkDotNet.Attributes;

namespace Norge360.Security.EndpointGuard.Benchmarks;

[MemoryDiagnoser]
public class Norge360SecurityEndpointGuardBenchmarks
{
    [Benchmark(Baseline = true)]
    public bool CanResolveEndpointGuardType() => typeof(global::Norge360.Security.EndpointGuard.ExternalEndpointGuard).IsAbstract;
}