// <copyright file="FixedWindowRuleOptionsBenchmarks.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using BenchmarkDotNet.Attributes;
using Norge360.Auth.API.Security;

namespace Norge360.Auth.Benchmarks;

[MemoryDiagnoser]
public class FixedWindowRuleOptionsBenchmarks
{
    private FixedWindowRuleOptions _rule = default!;

    [GlobalSetup]
    public void Setup()
    {
        _rule = new FixedWindowRuleOptions(PermitLimit: 10, WindowSeconds: 60, QueueLimit: 0);
    }

    [Benchmark]
    public object Build_RateLimiter_Options() => _rule.ToLimiterOptions();
}

