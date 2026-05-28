// <copyright file="MetadataAndValueObjectArchitectureTests.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

namespace Norge360.AspNetCore.Architecture.Tests;

public class MetadataAndValueObjectArchitectureTests
{
    [Fact]
    public void Metadata_types_should_be_immutable()
    {
        var metadataTypes = ArchitectureAssertions.GetProductionTypes()
            .Where(type => type.Name.EndsWith("Metadata", StringComparison.Ordinal));

        var violations = metadataTypes
            .Where(type => !type.IsInterface)
            .SelectMany(type => type.GetProperties(System.Reflection.BindingFlags.Public | System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.DeclaredOnly)
                .Where(property => property.SetMethod is not null &&
                                   property.SetMethod.IsPublic &&
                                   !IsInitOnlySetter(property.SetMethod))
                .Select(property => $"{type.FullName}.{property.Name}"));

        ArchitectureAssertions.AssertNoViolations(
            violations,
            "Metadata types should be immutable and must not expose public property setters");
    }

    [Fact]
    public void Route_diagnostics_metadata_should_remain_record_style_type()
    {
        var routeMetadataType = typeof(Norge360.AspNetCore.RequestContext.RouteDiagnosticsMetadata);

        Assert.True(
            routeMetadataType.IsSealed,
            "RouteDiagnosticsMetadata should remain a sealed lightweight value object.");
        Assert.True(
            ImplementsSelfEquatable(routeMetadataType),
            "RouteDiagnosticsMetadata should remain a lightweight value-object type with value semantics.");
    }

    [Fact]
    public void Security_headers_values_should_remain_immutable_record_style_type()
    {
        var securityHeadersType = typeof(Norge360.AspNetCore.Security.SecurityHeadersValues);

        Assert.True(
            securityHeadersType.IsSealed,
            "SecurityHeadersValues should remain a sealed immutable value carrier.");
        Assert.True(
            ImplementsSelfEquatable(securityHeadersType),
            "SecurityHeadersValues should remain a value-semantics carrier type.");

        var mutableProperties = securityHeadersType
            .GetProperties(System.Reflection.BindingFlags.Public | System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.DeclaredOnly)
            .Where(property => property.SetMethod is not null &&
                               property.SetMethod.IsPublic &&
                               !IsInitOnlySetter(property.SetMethod))
            .Select(property => property.Name)
            .ToArray();

        Assert.True(
            mutableProperties.Length == 0,
            $"SecurityHeadersValues must be immutable. Mutable properties: {string.Join(", ", mutableProperties)}");
    }

    private static bool IsInitOnlySetter(System.Reflection.MethodInfo setMethod) =>
        setMethod.ReturnParameter.GetRequiredCustomModifiers().Contains(typeof(System.Runtime.CompilerServices.IsExternalInit));

    private static bool ImplementsSelfEquatable(Type type) =>
        typeof(IEquatable<>).MakeGenericType(type).IsAssignableFrom(type);
}
