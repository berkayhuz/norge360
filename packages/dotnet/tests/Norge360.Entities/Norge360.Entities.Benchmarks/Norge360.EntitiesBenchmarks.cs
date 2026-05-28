// <copyright file="Norge360.EntitiesBenchmarks.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using BenchmarkDotNet.Attributes;

namespace Norge360.Entities.Benchmarks;

[MemoryDiagnoser]
public class Norge360EntitiesBenchmarks
{
    private readonly TestEntity _entity = new();

    [Benchmark(Baseline = true)]
    public void Activate() => _entity.Activate();

    [Benchmark]
    public void Deactivate() => _entity.Deactivate();

    [Benchmark]
    public void SetActiveTrue() => _entity.SetActive(true);

    [Benchmark]
    public Guid ReadId() => _entity.Id;

    private sealed class TestEntity : Norge360.Entities.EntityBase
    {
    }
}
