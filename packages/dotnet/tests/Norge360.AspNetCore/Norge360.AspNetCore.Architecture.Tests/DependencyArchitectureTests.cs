// <copyright file="DependencyArchitectureTests.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using NetArchTest.Rules;

namespace Norge360.AspNetCore.Architecture.Tests;

public class DependencyArchitectureTests
{
    private static readonly string[] DisallowedDependencyFragments =
    [
        ".Web",
        ".Api",
        ".Application",
        ".Infrastructure",
        ".Persistence",
        ".EntityFramework",
        ".Domain",
        ".Features",
        ".Modules",
        ".Workers",
        ".Jobs",
        ".Crm",
        ".Account",
        ".Auth",
        ".Public"
    ];

    [Fact]
    public void Production_types_must_not_depend_on_application_specific_layers()
    {
        var result = Types
            .InAssembly(ArchitectureTestAssembly.ProductionAssembly)
            .ShouldNot()
            .HaveDependencyOnAny(DisallowedDependencyFragments)
            .GetResult();

        ArchitectureAssertions.AssertRule(
            result,
            "Norge360.AspNetCore must not depend on application-specific layers such as Web, Api, Application, Infrastructure, Persistence, Domain, or feature modules");
    }
}
