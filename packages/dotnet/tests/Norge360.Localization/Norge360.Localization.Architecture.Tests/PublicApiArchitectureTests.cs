// <copyright file="PublicApiArchitectureTests.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>
using System.Reflection;

namespace Norge360.Localization.Architecture.Tests;

public class PublicApiArchitectureTests
{
    // TODO: Replace public field with a property or read-only abstraction in production code,
    // then remove this temporary exemption.
    private static readonly HashSet<string> AllowedPublicFields = new(StringComparer.Ordinal)
    {
        "Norge360.Localization.Norge360Cultures.SupportedCultureNames"
    };

    [Fact]
    public void Public_types_should_not_expose_mutable_public_fields()
    {
        var violations = ArchitectureAssertions.GetProductionTypes()
            .Where(type => type.IsPublic && !type.IsEnum)
            .SelectMany(type => type.GetFields(BindingFlags.Public | BindingFlags.Instance | BindingFlags.Static | BindingFlags.DeclaredOnly)
                .Where(field => !field.IsLiteral)
                .Select(field => $"{type.FullName}.{field.Name}"))
            .Where(memberName => !AllowedPublicFields.Contains(memberName));

        ArchitectureAssertions.AssertNoViolations(violations, "Public API should not expose mutable public fields.");
    }
}
