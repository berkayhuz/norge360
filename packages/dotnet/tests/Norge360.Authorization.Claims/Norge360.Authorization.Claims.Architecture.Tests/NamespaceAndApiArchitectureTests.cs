// <copyright file="NamespaceAndApiArchitectureTests.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using System.Security.Claims;

namespace Norge360.Authorization.Claims.Architecture.Tests;

public class NamespaceAndApiArchitectureTests
{
    [Fact]
    public void PermissionClaimReader_should_live_under_root_namespace()
    {
        var type = typeof(Norge360.Authorization.Claims.PermissionClaimReader);
        Assert.StartsWith("Norge360.Authorization.Claims", type.Namespace, StringComparison.Ordinal);
    }

    [Fact]
    public void PermissionClaimReader_should_be_static()
    {
        var type = typeof(Norge360.Authorization.Claims.PermissionClaimReader);
        Assert.True(type.IsAbstract && type.IsSealed, "PermissionClaimReader should remain a static helper.");
    }

    [Fact]
    [Trait("Category", "PerformanceGuardrail")]
    public void ReadPermissions_should_not_allocate_excessively_for_single_claim()
    {
        var identity = new ClaimsIdentity([new Claim("permission", "users.read users.write")]);
        var principal = new ClaimsPrincipal(identity);

        const int iterations = 5000;
        var allocated = MeasureAllocations(() => _ = Norge360.Authorization.Claims.PermissionClaimReader.ReadPermissions(principal), iterations);
        var bytesPerOperation = allocated / iterations;
        Assert.True(bytesPerOperation <= 2_100, $"Allocation guard exceeded for ReadPermissions: {bytesPerOperation} bytes/op.");
    }

    [Fact]
    [Trait("Category", "PerformanceGuardrail")]
    public void HasPermission_should_not_allocate_excessively_for_single_claim()
    {
        var identity = new ClaimsIdentity(
        [
            new Claim("permission", "users.read users.write")
        ]);
        var principal = new ClaimsPrincipal(identity);

        const int iterations = 5000;
        var allocated = MeasureAllocations(() => _ = Norge360.Authorization.Claims.PermissionClaimReader.HasPermission(principal, "users.read"), iterations);
        var bytesPerOperation = allocated / iterations;
        Assert.True(bytesPerOperation <= 450, $"Allocation guard exceeded for HasPermission: {bytesPerOperation} bytes/op.");
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
