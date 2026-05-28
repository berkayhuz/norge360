// <copyright file="DependencyArchitectureTests.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using NetArchTest.Rules;

namespace Norge360.AspNetCore.CurrentUser.Architecture.Tests;

public class DependencyArchitectureTests
{
    private static readonly string[] DisallowedDependencies =
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
    public void Assembly_should_not_depend_on_application_layers()
    {
        var result = Types.InAssembly(ArchitectureTestAssembly.ProductionAssembly)
            .That()
            .ResideInNamespace("Norge360.AspNetCore.CurrentUser")
            .ShouldNot()
            .HaveDependencyOnAny(DisallowedDependencies)
            .GetResult();

        ArchitectureAssertions.AssertRule(
            result,
            "Norge360.AspNetCore.CurrentUser should not depend on application-specific layers");
    }
}
