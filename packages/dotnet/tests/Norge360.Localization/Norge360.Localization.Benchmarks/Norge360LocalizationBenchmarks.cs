// <copyright file="Norge360LocalizationBenchmarks.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>
using BenchmarkDotNet.Attributes;
using Norge360.Localization;

namespace Norge360.Localization.Benchmarks;

[MemoryDiagnoser]
public class Norge360LocalizationBenchmarks
{
    [Benchmark(Baseline = true)]
    public string NormalizeOrDefault() => Norge360Cultures.NormalizeOrDefault("tr");

    [Benchmark]
    public bool IsSupportedCulture() => Norge360Cultures.IsSupportedCulture("en-US");

    [Benchmark]
    public object ToRequestCulture() => Norge360Cultures.ToRequestCulture("en");
}
