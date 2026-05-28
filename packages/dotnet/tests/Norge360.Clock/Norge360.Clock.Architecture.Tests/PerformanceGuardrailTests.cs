// <copyright file="PerformanceGuardrailTests.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

namespace Norge360.Clock.Architecture.Tests;

public class PerformanceGuardrailTests
{
    [Fact]
    [Trait("Category", "PerformanceGuardrail")]
    public void SystemClock_utc_now_should_not_allocate_excessively()
    {
        var clock = new Norge360.Clock.SystemClock();
        const int iterations = 50_000;
        var allocated = MeasureAllocations(() => _ = clock.UtcNow, iterations);
        var bytesPerOperation = allocated / iterations;
        Assert.True(bytesPerOperation <= 16, $"Allocation guard exceeded for SystemClock.UtcNow: {bytesPerOperation} bytes/op.");
    }

    private static long MeasureAllocations(Action action, int iterations)
    {
        for (var i = 0; i < 100; i++) action();
        GC.Collect();
        GC.WaitForPendingFinalizers();
        GC.Collect();

        var before = GC.GetAllocatedBytesForCurrentThread();
        for (var i = 0; i < iterations; i++) action();
        return GC.GetAllocatedBytesForCurrentThread() - before;
    }
}
