// <copyright file="NamespaceArchitectureTests.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>
namespace Norge360.Media.Storage.Architecture.Tests;

public class NamespaceArchitectureTests
{
    [Fact]
    public void Production_types_should_live_under_root_namespace()
    {
        var violations = ArchitectureAssertions.GetProductionTypes()
            .Where(type => type.Namespace is null || !type.Namespace.StartsWith("Norge360.Media.Storage", StringComparison.Ordinal))
            .Select(type => type.FullName ?? type.Name);

        ArchitectureAssertions.AssertNoViolations(violations, "Production types should live under Norge360.Media.Storage namespace.");
    }
}
