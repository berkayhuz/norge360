// <copyright file="SupportTypeArchitectureTests.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

namespace Norge360.AspNetCore.Architecture.Tests;

public class SupportTypeArchitectureTests
{
    [Fact]
    public void Types_ending_with_support_must_be_static_classes()
    {
        var supportTypes = ArchitectureAssertions.GetProductionTypes()
            .Where(type => type.Name.EndsWith("Support", StringComparison.Ordinal));

        var violations = supportTypes
            .Where(type => !(type.IsAbstract && type.IsSealed))
            .Select(type => type.FullName ?? type.Name);

        ArchitectureAssertions.AssertNoViolations(
            violations,
            "Types ending with Support should be static classes");
    }

    [Fact]
    public void Public_helpers_must_not_be_abstract_static_only_types()
    {
        var publicTypes = ArchitectureAssertions.GetProductionTypes()
            .Where(type => type.IsPublic);

        var violations = publicTypes
            .Where(type => type.IsAbstract &&
                           !type.IsSealed &&
                           !type.IsInterface &&
                           !type.GetMembers(System.Reflection.BindingFlags.Public | System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.DeclaredOnly)
                               .Any(member => member is System.Reflection.MethodBase method && !method.IsSpecialName))
            .Select(type => type.FullName ?? type.Name);

        ArchitectureAssertions.AssertNoViolations(
            violations,
            "Public helper types should not be abstract classes used as static-only containers");
    }

    [Fact]
    public void Null_scope_must_remain_internal()
    {
        var nullScopeType = ArchitectureTestAssembly.ProductionAssembly.GetType("Norge360.AspNetCore.RequestContext.NullScope", throwOnError: true)!;

        Assert.False(
            nullScopeType.IsPublic,
            "NullScope is an internal implementation detail and must not become public.");
    }
}
