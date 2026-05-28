// <copyright file="AsyncNamingArchitectureTests.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

namespace Norge360.AspNetCore.Architecture.Tests;

public class AsyncNamingArchitectureTests
{
    [Fact]
    public void Public_task_returning_methods_should_end_with_async_unless_framework_override_requires_other_name()
    {
        var violations = ArchitectureAssertions.GetProductionTypes()
            .Where(type => type.IsPublic)
            .SelectMany(type => type
                .GetMethods(System.Reflection.BindingFlags.Public | System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.Static | System.Reflection.BindingFlags.DeclaredOnly)
                .Where(method => !method.IsSpecialName)
                .Where(method => method.ReturnType == typeof(Task) ||
                                 (method.ReturnType.IsGenericType && method.ReturnType.GetGenericTypeDefinition() == typeof(Task<>)) ||
                                 method.ReturnType == typeof(ValueTask) ||
                                 (method.ReturnType.IsGenericType && method.ReturnType.GetGenericTypeDefinition() == typeof(ValueTask<>)))
                .Where(method => !method.Name.EndsWith("Async", StringComparison.Ordinal))
                .Where(method => !IsFrameworkOverride(method))
                .Select(method => $"{type.FullName}.{method.Name}"));

        ArchitectureAssertions.AssertNoViolations(
            violations,
            "Public methods returning Task or ValueTask should end with Async unless an ASP.NET Core framework override defines the method name");
    }

    private static bool IsFrameworkOverride(System.Reflection.MethodInfo method)
    {
        if (!method.IsVirtual)
        {
            return false;
        }

        var baseDefinition = method.GetBaseDefinition();
        return baseDefinition.DeclaringType?.Assembly != method.DeclaringType?.Assembly;
    }
}
