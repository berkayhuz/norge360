// <copyright file="PerformanceGuardrailTests.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using Norge360.AspNetCore.Security;
using Norge360.Localization;

namespace Norge360.AspNetCore.Architecture.Tests;

public class PerformanceGuardrailTests
{
    [Fact]
    [Trait("Category", "PerformanceGuardrail")]
    public void Normalize_should_remain_zero_allocation_for_supported_cultures()
    {
        static void ExerciseHotPath()
        {
            _ = Norge360Cultures.Normalize("tr");
            _ = Norge360Cultures.Normalize("en");
            _ = Norge360Cultures.Normalize("tr-TR");
            _ = Norge360Cultures.Normalize("en-US");
            _ = Norge360Cultures.Normalize("tr_TR");
            _ = Norge360Cultures.Normalize("en_US");
        }

        var allocatedBytes = MeasureAllocations(ExerciseHotPath, iterations: 20_000);

        Assert.True(
            allocatedBytes == 0,
            $"Expected zero allocations for supported culture normalization hot path, but measured {allocatedBytes} bytes.");
    }

    [Fact]
    [Trait("Category", "PerformanceGuardrail")]
    public void IsValidOrigin_should_remain_zero_allocation_for_https_and_localhost_http()
    {
        static void ExerciseHotPath()
        {
            _ = SecuritySupport.IsValidOrigin("https://example.com", allowHttpForLocalhostOnly: true);
            _ = SecuritySupport.IsValidOrigin("https://example.com:443", allowHttpForLocalhostOnly: true);
            _ = SecuritySupport.IsValidOrigin("http://localhost:5000", allowHttpForLocalhostOnly: true);
        }

        var allocatedBytes = MeasureAllocations(ExerciseHotPath, iterations: 20_000);

        Assert.True(
            allocatedBytes == 0,
            $"Expected zero allocations for origin validation hot path, but measured {allocatedBytes} bytes.");
    }

    private static long MeasureAllocations(Action action, int iterations)
    {
        for (var i = 0; i < 200; i++)
        {
            action();
        }

        GC.Collect();
        GC.WaitForPendingFinalizers();
        GC.Collect();

        var before = GC.GetAllocatedBytesForCurrentThread();

        for (var i = 0; i < iterations; i++)
        {
            action();
        }

        return GC.GetAllocatedBytesForCurrentThread() - before;
    }
}
