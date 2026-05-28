// <copyright file="DesignArchitectureTests.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

namespace Norge360.Exceptions.Architecture.Tests;

public class DesignArchitectureTests
{
    [Fact]
    public void Public_exceptions_should_derive_from_Exception()
    {
        var violations = ArchitectureAssertions.GetProductionTypes()
            .Where(type => type.IsPublic)
            .Where(type => !typeof(Exception).IsAssignableFrom(type))
            .Select(type => type.FullName ?? type.Name);

        ArchitectureAssertions.AssertNoViolations(violations, "All public types in Norge360.Exceptions should derive from Exception."
        );
    }
}
