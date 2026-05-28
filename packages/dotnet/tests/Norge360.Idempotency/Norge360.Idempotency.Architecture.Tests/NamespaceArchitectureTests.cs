namespace Norge360.Idempotency.Architecture.Tests;

public class NamespaceArchitectureTests
{
    [Fact]
    public void Production_types_should_live_under_root_namespace()
    {
        var violations = ArchitectureAssertions.GetProductionTypes()
            .Where(type => type.Namespace is null || !type.Namespace.StartsWith("Norge360.Idempotency", StringComparison.Ordinal))
            .Select(type => type.FullName ?? type.Name);

        ArchitectureAssertions.AssertNoViolations(violations, "Production types should live under Norge360.Idempotency namespace.");
    }
}
