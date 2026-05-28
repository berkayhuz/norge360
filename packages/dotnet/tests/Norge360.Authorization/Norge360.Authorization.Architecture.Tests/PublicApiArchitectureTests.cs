// <copyright file="PublicApiArchitectureTests.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using System.Reflection;

namespace Norge360.Authorization.Architecture.Tests;

public class PublicApiArchitectureTests
{
    [Fact]
    public void Public_types_should_not_expose_public_fields()
    {
        var violations = ArchitectureAssertions.GetProductionTypes()
            .Where(t => t.IsPublic && !t.IsEnum)
            .SelectMany(t => t.GetFields(BindingFlags.Public | BindingFlags.Instance | BindingFlags.Static | BindingFlags.DeclaredOnly)
                .Where(f => !f.IsLiteral)
                .Select(f => $"{t.FullName}.{f.Name}"));

        ArchitectureAssertions.AssertNoViolations(violations, "Public API should not expose mutable public fields.");
    }
}
