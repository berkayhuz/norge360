using System.Reflection;

namespace Norge360.Idempotency.Architecture.Tests;

public class PublicApiArchitectureTests
{
    [Fact]
    public void Public_types_should_not_expose_mutable_public_fields()
    {
        var violations = ArchitectureAssertions.GetProductionTypes()
            .Where(type => type.IsPublic && !type.IsEnum)
            .SelectMany(type => type.GetFields(BindingFlags.Public | BindingFlags.Instance | BindingFlags.Static | BindingFlags.DeclaredOnly)
                .Where(field => !field.IsLiteral)
                .Select(field => $"{type.FullName}.{field.Name}"));

        ArchitectureAssertions.AssertNoViolations(violations, "Public API should not expose mutable public fields.");
    }
}
