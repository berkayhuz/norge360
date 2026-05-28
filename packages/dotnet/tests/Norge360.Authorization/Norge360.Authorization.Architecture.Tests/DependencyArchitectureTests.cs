// <copyright file="DependencyArchitectureTests.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using NetArchTest.Rules;

namespace Norge360.Authorization.Architecture.Tests;

public class DependencyArchitectureTests
{
    private static readonly string[] DisallowedDependencies =
    [
        ".Web", ".Api", ".Application", ".Infrastructure", ".Persistence", ".EntityFramework",
        ".Features", ".Modules", ".Workers", ".Jobs", ".Crm", ".Account", ".Auth", ".Public"
    ];

    [Fact]
    public void Should_not_depend_on_application_layers()
    {
        var result = Types.InAssembly(ArchitectureTestAssembly.ProductionAssembly)
            .That()
            .ResideInNamespace("Norge360.Authorization")
            .ShouldNot()
            .HaveDependencyOnAny(DisallowedDependencies)
            .GetResult();

        ArchitectureAssertions.AssertRule(result, "Norge360.Authorization should not depend on application layers.");
    }
}
