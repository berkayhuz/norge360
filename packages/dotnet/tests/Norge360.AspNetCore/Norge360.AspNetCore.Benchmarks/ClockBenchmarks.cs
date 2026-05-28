// <copyright file="ClockBenchmarks.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using BenchmarkDotNet.Attributes;
using Norge360.Clock;

namespace Norge360.AspNetCore.Benchmarks;

[MemoryDiagnoser]
public class ClockBenchmarks
{
    private readonly IClock _clock = new SystemClock();

    [Benchmark(Baseline = true)]
    public DateTimeOffset ReadUtcNow() => _clock.UtcNow;

    [Benchmark]
    public DateTime ReadUtcDateTime() => _clock.UtcDateTime;
}
