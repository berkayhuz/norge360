// <copyright file="DependencyArchitectureTests.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using NetArchTest.Rules;

namespace Norge360.Authorization.AspNetCore.Architecture.Tests;

public class DependencyArchitectureTests
{
    [Fact]
    public void Should_only_depend_on_shared_authorization_layers()
    {
        var result = Types.InAssembly(ArchitectureTestAssembly.ProductionAssembly)
            .That()
            .ResideInNamespace("Norge360.Authorization.AspNetCore")
            .ShouldNot()
            .HaveDependencyOnAny(".Web", ".Api", ".Application", ".Infrastructure", ".Persistence", ".EntityFramework")
            .GetResult();

        ArchitectureAssertions.AssertRule(result, "Norge360.Authorization.AspNetCore should not depend on app/infrastructure layers.");
    }
}
