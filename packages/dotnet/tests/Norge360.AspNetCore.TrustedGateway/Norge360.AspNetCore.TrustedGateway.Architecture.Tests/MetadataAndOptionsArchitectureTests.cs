// <copyright file="MetadataAndOptionsArchitectureTests.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

namespace Norge360.AspNetCore.TrustedGateway.Architecture.Tests;

public class MetadataAndOptionsArchitectureTests
{
    [Fact]
    public void Types_ending_with_validation_result_or_signed_headers_should_be_records()
    {
        var targetTypes = ArchitectureAssertions.GetProductionTypes()
            .Where(type => type.IsPublic)
            .Where(type => type.Name is "TrustedGatewayValidationResult" or "TrustedGatewaySignedHeaders")
            .ToArray();

        var violations = targetTypes
            .Where(type => !IsRecord(type))
            .Select(type => type.FullName ?? type.Name);

        ArchitectureAssertions.AssertNoViolations(
            violations,
            "Validation result and signed headers should remain record-style value carriers");
    }

    [Fact]
    public void Option_types_should_remain_sealed()
    {
        var violations = ArchitectureAssertions.GetProductionTypes()
            .Where(type => type.IsClass && type.IsPublic && type.Name.EndsWith("Options", StringComparison.Ordinal))
            .Where(type => !type.IsSealed)
            .Select(type => type.FullName ?? type.Name);

        ArchitectureAssertions.AssertNoViolations(
            violations,
            "Option types should remain sealed");
    }

    private static bool IsRecord(Type type) =>
        type.GetMethod("<Clone>$", System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic) is not null ||
        type.GetProperty("EqualityContract", System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic) is not null;
}
