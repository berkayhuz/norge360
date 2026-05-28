// <copyright file="SecuritySupportBenchmarks.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using BenchmarkDotNet.Attributes;
using Norge360.AspNetCore.Security;

namespace Norge360.AspNetCore.Benchmarks;

[MemoryDiagnoser]
public class SecuritySupportBenchmarks
{
    [Benchmark]
    public bool IsValidOrigin_Https() =>
        SecuritySupport.IsValidOrigin("https://norge360.com", allowHttpForLocalhostOnly: true);

    [Benchmark]
    public bool IsValidOrigin_LocalhostHttp() =>
        SecuritySupport.IsValidOrigin("http://localhost", allowHttpForLocalhostOnly: true);

    [Benchmark]
    public bool LooksLikeHostName_Valid() =>
        SecuritySupport.LooksLikeHostName("gateway.norge360.internal");

    [Benchmark]
    public bool LooksLikeHostName_Invalid() =>
        SecuritySupport.LooksLikeHostName("https://gateway.norge360.internal/path");
}
