// <copyright file="Norge360CulturesBenchmarks.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using BenchmarkDotNet.Attributes;
using Norge360.Localization;

namespace Norge360.AspNetCore.Benchmarks;

[MemoryDiagnoser]
public class Norge360CulturesBenchmarks
{
    [Benchmark]
    public string? Normalize_TurkishShort() => Norge360Cultures.Normalize("tr");

    [Benchmark]
    public string? Normalize_EnglishShort() => Norge360Cultures.Normalize("en");

    [Benchmark]
    public string? Normalize_TurkishFull() => Norge360Cultures.Normalize("tr-TR");

    [Benchmark]
    public string? Normalize_EnglishFull() => Norge360Cultures.Normalize("en-US");

    [Benchmark]
    public string? Normalize_TurkishUnderscore() => Norge360Cultures.Normalize("tr_TR");

    [Benchmark]
    public string? Normalize_UnsupportedCulture() => Norge360Cultures.Normalize("zz-ZZ");
}
