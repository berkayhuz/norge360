using NetArchTest.Rules;

namespace Norge360.Idempotency.Redis.Architecture.Tests;

public class DependencyArchitectureTests
{
    private static readonly string[] DisallowedDependencies =
    [
        ".Web", ".Api", ".Application", ".Infrastructure", ".Persistence", ".EntityFramework",
        ".Domain", ".Features", ".Modules", ".Workers", ".Jobs", ".Crm", ".Account", ".Auth", ".Public"
    ];

    [Fact]
    public void Should_not_depend_on_application_layers()
    {
        var result = Types.InAssembly(ArchitectureTestAssembly.ProductionAssembly)
            .That()
            .ResideInNamespace("Norge360.Idempotency.Redis")
            .ShouldNot()
            .HaveDependencyOnAny(DisallowedDependencies)
            .GetResult();

        ArchitectureAssertions.AssertRule(result, "Norge360.Idempotency.Redis should not depend on application-specific layers.");
    }
}
