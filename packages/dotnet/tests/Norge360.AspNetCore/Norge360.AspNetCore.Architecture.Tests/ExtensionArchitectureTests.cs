// <copyright file="ExtensionArchitectureTests.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using Microsoft.AspNetCore.Builder;
using Microsoft.Extensions.DependencyInjection;

namespace Norge360.AspNetCore.Architecture.Tests;

public class ExtensionArchitectureTests
{
    [Fact]
    public void Dependency_injection_types_must_be_static_and_suffixed_with_extensions()
    {
        var types = ArchitectureAssertions.GetProductionTypes()
            .Where(type => type.Namespace?.Contains(".DependencyInjection", StringComparison.Ordinal) == true)
            .ToArray();

        var violations = types
            .Where(type => !(type.IsAbstract && type.IsSealed) ||
                           !type.Name.EndsWith("Extensions", StringComparison.Ordinal))
            .Select(type => type.FullName ?? type.Name);

        ArchitectureAssertions.AssertNoViolations(
            violations,
            "Types under .DependencyInjection must be static classes ending with Extensions");
    }

    [Fact]
    public void Public_extension_methods_must_be_declared_on_static_classes()
    {
        var violations = ArchitectureAssertions.GetProductionTypes()
            .SelectMany(type => type.GetMethods(System.Reflection.BindingFlags.Public | System.Reflection.BindingFlags.Static | System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.DeclaredOnly)
                .Where(method => method.IsDefined(typeof(System.Runtime.CompilerServices.ExtensionAttribute), inherit: false))
                .Where(method => !(type.IsAbstract && type.IsSealed))
                .Select(method => $"{type.FullName}.{method.Name}"));

        ArchitectureAssertions.AssertNoViolations(
            violations,
            "Public extension methods must be declared in static classes");
    }

    [Fact]
    public void Service_registration_extensions_should_return_iservicecollection()
    {
        var violations = ArchitectureAssertions.GetProductionTypes()
            .SelectMany(type => type.GetMethods(System.Reflection.BindingFlags.Public | System.Reflection.BindingFlags.Static | System.Reflection.BindingFlags.DeclaredOnly)
                .Where(method => method.Name.StartsWith("Add", StringComparison.Ordinal))
                .Where(method => method.IsDefined(typeof(System.Runtime.CompilerServices.ExtensionAttribute), inherit: false))
                .Where(method => method.GetParameters().FirstOrDefault()?.ParameterType == typeof(IServiceCollection))
                .Where(method => method.ReturnType != typeof(IServiceCollection))
                .Select(method => $"{type.FullName}.{method.Name} returns {method.ReturnType.Name}"));

        ArchitectureAssertions.AssertNoViolations(
            violations,
            "Dependency injection extension methods should return IServiceCollection");
    }

    [Fact]
    public void Application_pipeline_extensions_should_return_builder_type()
    {
        var violations = ArchitectureAssertions.GetProductionTypes()
            .SelectMany(type => type.GetMethods(System.Reflection.BindingFlags.Public | System.Reflection.BindingFlags.Static | System.Reflection.BindingFlags.DeclaredOnly)
                .Where(method => method.Name.StartsWith("Use", StringComparison.Ordinal))
                .Where(method => method.IsDefined(typeof(System.Runtime.CompilerServices.ExtensionAttribute), inherit: false))
                .Where(method => method.GetParameters().Length > 0)
                .Where(method => method.GetParameters()[0].ParameterType == typeof(IApplicationBuilder))
                .Where(method => method.ReturnType != typeof(IApplicationBuilder))
                .Select(method => $"{type.FullName}.{method.Name} returns {method.ReturnType.Name}"));

        ArchitectureAssertions.AssertNoViolations(
            violations,
            "Middleware or app pipeline extension methods should return IApplicationBuilder when extending IApplicationBuilder");
    }
}
