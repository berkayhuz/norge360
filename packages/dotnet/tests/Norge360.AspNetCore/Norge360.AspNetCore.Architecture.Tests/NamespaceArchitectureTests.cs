// <copyright file="NamespaceArchitectureTests.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

namespace Norge360.AspNetCore.Architecture.Tests;

public class NamespaceArchitectureTests
{
    [Fact]
    public void Production_types_must_live_under_norge360_aspnetcore_root_namespace()
    {
        var violations = ArchitectureAssertions.GetProductionTypes()
            .Where(type => type.Namespace is null ||
                           !type.Namespace.StartsWith(ArchitectureTestAssembly.ProductionRootNamespace, StringComparison.Ordinal))
            .Select(type => type.FullName ?? type.Name);

        ArchitectureAssertions.AssertNoViolations(
            violations,
            "All production types in Norge360.AspNetCore must live under the Norge360.AspNetCore root namespace and cannot use the global namespace");
    }

    [Fact]
    public void Test_types_must_live_under_test_root_namespace()
    {
        var testAssembly = typeof(NamespaceArchitectureTests).Assembly;
        var violations = testAssembly
            .GetTypes()
            .Where(type => type.Namespace is not null)
            .Where(type => !type.Namespace!.StartsWith("Norge360.AspNetCore.Architecture.Tests", StringComparison.Ordinal))
            .Select(type => type.FullName ?? type.Name);

        ArchitectureAssertions.AssertNoViolations(
            violations,
            "All test types must live under the Norge360.AspNetCore.Architecture.Tests namespace");
    }
}
