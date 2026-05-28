// <copyright file="DesignArchitectureTests.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using System.Reflection;

namespace Norge360.AspNetCore.TrustedGateway.Architecture.Tests;

public class DesignArchitectureTests
{
    [Fact]
    public void Types_ending_with_validator_signer_or_protector_should_be_sealed()
    {
        var violations = ArchitectureAssertions.GetProductionTypes()
            .Where(type => type.IsClass && type.IsPublic)
            .Where(type =>
                type.Name.EndsWith("Validator", StringComparison.Ordinal) ||
                type.Name.EndsWith("Signer", StringComparison.Ordinal) ||
                type.Name.EndsWith("Protector", StringComparison.Ordinal))
            .Where(type => !type.IsSealed)
            .Select(type => type.FullName ?? type.Name);

        ArchitectureAssertions.AssertNoViolations(
            violations,
            "Public validator/signer/protector types should be sealed");
    }

    [Fact]
    public void Public_types_should_not_expose_public_fields()
    {
        var violations = ArchitectureAssertions.GetProductionTypes()
            .Where(type => type.IsPublic)
            .Where(type => !type.IsEnum)
            .SelectMany(type => type.GetFields(BindingFlags.Public | BindingFlags.Instance | BindingFlags.Static | BindingFlags.DeclaredOnly)
                .Where(field => !field.IsLiteral)
                .Select(field => $"{type.FullName}.{field.Name}"));

        ArchitectureAssertions.AssertNoViolations(
            violations,
            "Public types should not expose public fields");
    }
}
