// <copyright file="PublicApiHardeningArchitectureTests.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using System.Runtime.CompilerServices;
using System.Reflection;

namespace Norge360.AspNetCore.Architecture.Tests;

public class PublicApiHardeningArchitectureTests
{
    private static readonly string[] DisallowedPublicApiNamespaceFragments =
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
    public void Production_assembly_should_not_expose_internals_to_friend_assemblies()
    {
        var friendAssemblies = ArchitectureTestAssembly.ProductionAssembly
            .GetCustomAttributes(typeof(InternalsVisibleToAttribute), inherit: false)
            .Cast<InternalsVisibleToAttribute>()
            .Select(attribute => attribute.AssemblyName)
            .OrderBy(name => name, StringComparer.Ordinal)
            .ToArray();

        Assert.True(
            friendAssemblies.Length == 0,
            $"Norge360.AspNetCore should not expose internals via InternalsVisibleTo. Found: {string.Join(", ", friendAssemblies)}");
    }

    [Fact]
    public void Public_api_should_not_leak_application_specific_namespaces_or_disallowed_norge360_layers()
    {
        var publicTypes = ArchitectureAssertions.GetProductionTypes()
            .Where(type => type.IsPublic)
            .ToArray();

        var signatureTypes = publicTypes
            .SelectMany(GetPublicSurfaceReferencedTypes)
            .Distinct()
            .ToArray();

        var violations = signatureTypes
            .Where(type => !type.IsGenericParameter)
            .Where(type => type.Namespace is not null)
            .Where(type =>
            {
                var typeNamespace = type.Namespace!;
                return DisallowedPublicApiNamespaceFragments.Any(fragment => typeNamespace.Contains(fragment, StringComparison.Ordinal));
            })
            .Select(type => type.FullName ?? type.Name)
            .Concat(
                signatureTypes
                    .Where(type => type.Namespace is not null)
                    .Where(type =>
                    {
                        var typeNamespace = type.Namespace!;
                        return typeNamespace.StartsWith("Norge360.", StringComparison.Ordinal) &&
                               !typeNamespace.StartsWith("Norge360.AspNetCore", StringComparison.Ordinal) &&
                               !typeNamespace.StartsWith("Norge360.Localization", StringComparison.Ordinal);
                    })
                    .Select(type => type.FullName ?? type.Name));

        ArchitectureAssertions.AssertNoViolations(
            violations,
            "Public API surface should not leak application-specific namespaces or disallowed Norge360 layers");
    }

    [Fact]
    public void Utility_classes_should_not_expose_public_instance_constructors()
    {
        var utilityTypes = ArchitectureAssertions.GetProductionTypes()
            .Where(type => type.IsPublic && type.IsClass)
            .Where(type => type.Name.EndsWith("Support", StringComparison.Ordinal) ||
                           type.Name.EndsWith("Extensions", StringComparison.Ordinal) ||
                           type.Name.EndsWith("Writer", StringComparison.Ordinal))
            .ToArray();

        var violations = utilityTypes
            .SelectMany(type => type.GetConstructors(System.Reflection.BindingFlags.Public | System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.DeclaredOnly)
                .Select(constructor => $"{type.FullName}.{constructor.Name}()"));

        ArchitectureAssertions.AssertNoViolations(
            violations,
            "Utility classes should not expose public instance constructors");
    }

    private static IEnumerable<Type> GetPublicSurfaceReferencedTypes(Type type)
    {
        yield return type;

        foreach (var property in type.GetProperties(System.Reflection.BindingFlags.Public | System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.Static | System.Reflection.BindingFlags.DeclaredOnly))
        {
            foreach (var referencedType in ExpandType(property.PropertyType))
            {
                yield return referencedType;
            }
        }

        foreach (var method in type.GetMethods(System.Reflection.BindingFlags.Public | System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.Static | System.Reflection.BindingFlags.DeclaredOnly))
        {
            if (method.IsSpecialName)
            {
                continue;
            }

            foreach (var referencedType in ExpandType(method.ReturnType))
            {
                yield return referencedType;
            }

            foreach (var parameter in method.GetParameters())
            {
                foreach (var referencedType in ExpandType(parameter.ParameterType))
                {
                    yield return referencedType;
                }
            }
        }
    }

    private static IEnumerable<Type> ExpandType(Type type)
    {
        if (type.HasElementType && type.GetElementType() is { } elementType)
        {
            foreach (var nestedType in ExpandType(elementType))
            {
                yield return nestedType;
            }
        }

        if (type.IsGenericType)
        {
            yield return type.GetGenericTypeDefinition();

            foreach (var genericType in type.GetGenericArguments().SelectMany(ExpandType))
            {
                yield return genericType;
            }
        }
        else
        {
            yield return type;
        }
    }
}
