// <copyright file="PerformanceGuardrailTests.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

namespace Norge360.CurrentUser.Architecture.Tests;

public class PerformanceGuardrailTests
{
    [Fact]
    [Trait("Category", "PerformanceGuardrail")]
    public void IsAuthenticated_extension_should_not_allocate_excessively()
    {
        var user = new StubCurrentUserService { UserId = Guid.NewGuid() };
        const int iterations = 50_000;
        var allocated = MeasureAllocations(() => _ = user.IsAuthenticated(), iterations);
        var bytesPerOperation = allocated / iterations;
        Assert.True(bytesPerOperation <= 8, $"Allocation guard exceeded for CurrentUserServiceExtensions.IsAuthenticated: {bytesPerOperation} bytes/op.");
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

    private sealed class StubCurrentUserService : Norge360.CurrentUser.ICurrentUserService
    {
        public Guid UserId { get; init; }
        public bool IsAuthenticated => UserId != Guid.Empty;
        public string? UserName => null;
        public string? Email => null;
        public IReadOnlyCollection<string> Roles => [];
        public IReadOnlyCollection<string> Permissions => [];
        public bool IsInRole(string role) => false;
        public bool HasPermission(string permission) => false;
    }
}
