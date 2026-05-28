// <copyright file="PublicApiArchitectureTests.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

namespace Norge360.AspNetCore.Architecture.Tests;

public class PublicApiArchitectureTests
{
    [Fact]
    public void Public_types_should_not_expose_public_fields()
    {
        var violations = ArchitectureAssertions.GetProductionTypes()
            .Where(type => type.IsPublic)
            .SelectMany(type => type
                .GetFields(System.Reflection.BindingFlags.Public | System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.Static | System.Reflection.BindingFlags.DeclaredOnly)
                .Where(field => !field.IsLiteral)
                .Select(field => $"{type.FullName}.{field.Name}"));

        ArchitectureAssertions.AssertNoViolations(
            violations,
            "Public production types should not expose public fields");
    }

    [Fact]
    public void Public_types_should_not_expose_public_setters()
    {
        var violations = ArchitectureAssertions.GetProductionTypes()
            .Where(type => type.IsPublic)
            .SelectMany(type => type
                .GetProperties(System.Reflection.BindingFlags.Public | System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.Static | System.Reflection.BindingFlags.DeclaredOnly)
                .Where(property => property.SetMethod is not null &&
                                   property.SetMethod.IsPublic &&
                                   !IsInitOnlySetter(property.SetMethod))
                .Select(property => $"{type.FullName}.{property.Name}"));

        ArchitectureAssertions.AssertNoViolations(
            violations,
            "Public production types should not expose public setters unless explicitly required");
    }

    [Fact]
    public void Public_constants_should_be_restricted_to_stable_header_or_protocol_names()
    {
        var violations = ArchitectureAssertions.GetProductionTypes()
            .Where(type => type.IsPublic)
            .SelectMany(type => type
                .GetFields(System.Reflection.BindingFlags.Public | System.Reflection.BindingFlags.Static | System.Reflection.BindingFlags.DeclaredOnly)
                .Where(field => field.IsLiteral)
                .Where(field => !field.Name.EndsWith("HeaderName", StringComparison.Ordinal) &&
                                !field.Name.EndsWith("ProtocolName", StringComparison.Ordinal))
                .Select(field => $"{type.FullName}.{field.Name}"));

        ArchitectureAssertions.AssertNoViolations(
            violations,
            "Public constants should be limited to stable header or protocol names");
    }

    private static bool IsInitOnlySetter(System.Reflection.MethodInfo setMethod) =>
        setMethod.ReturnParameter.GetRequiredCustomModifiers().Contains(typeof(System.Runtime.CompilerServices.IsExternalInit));
}
