// <copyright file="LocalizationProviderArchitectureTests.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using Microsoft.AspNetCore.Localization;

namespace Norge360.AspNetCore.Architecture.Tests;

public class LocalizationProviderArchitectureTests
{
    [Fact]
    public void Request_culture_providers_must_follow_expected_shape()
    {
        var providerTypes = ArchitectureAssertions.GetProductionTypes()
            .Where(type => type.Name.EndsWith("RequestCultureProvider", StringComparison.Ordinal))
            .ToArray();

        var violations = providerTypes
            .Where(type => !typeof(RequestCultureProvider).IsAssignableFrom(type) ||
                           !type.IsSealed ||
                           type.Namespace != "Norge360.AspNetCore.Localization.Providers")
            .Select(type => type.FullName ?? type.Name);

        ArchitectureAssertions.AssertNoViolations(
            violations,
            "Request culture providers must inherit RequestCultureProvider, be sealed, and live under Norge360.AspNetCore.Localization.Providers");
    }

    [Fact]
    public void Request_culture_providers_must_not_expose_public_mutable_fields()
    {
        var providerTypes = ArchitectureAssertions.GetProductionTypes()
            .Where(type => type.Name.EndsWith("RequestCultureProvider", StringComparison.Ordinal));

        var violations = providerTypes
            .SelectMany(type => type
                .GetFields(System.Reflection.BindingFlags.Public | System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.DeclaredOnly)
                .Where(field => !field.IsInitOnly)
                .Select(field => $"{type.FullName}.{field.Name}"));

        ArchitectureAssertions.AssertNoViolations(
            violations,
            "Request culture provider classes should not expose public mutable state");
    }
}
