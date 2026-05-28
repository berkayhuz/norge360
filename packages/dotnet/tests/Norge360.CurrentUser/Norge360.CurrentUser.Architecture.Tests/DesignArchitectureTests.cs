// <copyright file="DesignArchitectureTests.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using System.Reflection;

namespace Norge360.CurrentUser.Architecture.Tests;

public class DesignArchitectureTests
{
    [Fact]
    public void Extension_container_should_remain_static()
    {
        var extensionType = typeof(Norge360.CurrentUser.CurrentUserServiceExtensions);
        Assert.True(extensionType.IsAbstract && extensionType.IsSealed, "CurrentUserServiceExtensions should remain a static class.");
    }

    [Fact]
    public void Public_types_should_not_expose_public_fields()
    {
        var violations = ArchitectureAssertions.GetProductionTypes()
            .Where(type => type.IsPublic && !type.IsEnum)
            .SelectMany(type => type.GetFields(BindingFlags.Public | BindingFlags.Instance | BindingFlags.Static | BindingFlags.DeclaredOnly)
                .Where(field => !field.IsLiteral)
                .Select(field => $"{type.FullName}.{field.Name}"));

        ArchitectureAssertions.AssertNoViolations(violations, "Public API should not expose mutable public fields.");
    }
}
