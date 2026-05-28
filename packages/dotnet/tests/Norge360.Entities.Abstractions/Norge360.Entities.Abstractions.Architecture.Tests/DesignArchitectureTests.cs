// <copyright file="DesignArchitectureTests.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

namespace Norge360.Entities.Abstractions.Architecture.Tests;

public class DesignArchitectureTests
{
    [Fact]
    public void All_public_types_should_be_interfaces()
    {
        var violations = ArchitectureAssertions.GetProductionTypes()
            .Where(type => type.IsPublic && !type.IsInterface)
            .Select(type => type.FullName ?? type.Name);

        ArchitectureAssertions.AssertNoViolations(violations, "Norge360.Entities.Abstractions should only expose interfaces."
        );
    }
}
