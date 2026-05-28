// <copyright file="ServiceDesignArchitectureTests.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using System.Reflection;

namespace Norge360.AspNetCore.CurrentUser.Architecture.Tests;

public class ServiceDesignArchitectureTests
{
    [Fact]
    public void HttpCurrentUserService_should_remain_sealed()
    {
        Assert.True(
            typeof(Norge360.AspNetCore.CurrentUser.HttpCurrentUserService).IsSealed,
            "HttpCurrentUserService should remain sealed to keep behavior explicit and avoid subclass side effects.");
    }

    [Fact]
    public void Public_types_should_not_expose_public_fields()
    {
        var violations = ArchitectureAssertions.GetProductionTypes()
            .Where(type => type.IsPublic)
            .SelectMany(type => type.GetFields(BindingFlags.Public | BindingFlags.Instance | BindingFlags.Static | BindingFlags.DeclaredOnly)
                .Select(field => $"{type.FullName}.{field.Name}"));

        ArchitectureAssertions.AssertNoViolations(
            violations,
            "Public types should not expose public fields");
    }
}
