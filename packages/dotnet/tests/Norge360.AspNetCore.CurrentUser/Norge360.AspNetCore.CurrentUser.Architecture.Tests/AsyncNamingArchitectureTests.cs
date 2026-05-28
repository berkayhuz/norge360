// <copyright file="AsyncNamingArchitectureTests.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using System.Reflection;

namespace Norge360.AspNetCore.CurrentUser.Architecture.Tests;

public class AsyncNamingArchitectureTests
{
    [Fact]
    public void Public_methods_returning_task_should_end_with_async()
    {
        var violations = ArchitectureAssertions.GetProductionTypes()
            .Where(type => type.IsPublic)
            .SelectMany(type => type.GetMethods(BindingFlags.Public | BindingFlags.Instance | BindingFlags.Static | BindingFlags.DeclaredOnly))
            .Where(method => !method.IsSpecialName)
            .Where(method => method.ReturnType == typeof(Task) ||
                             method.ReturnType == typeof(ValueTask) ||
                             (method.ReturnType.IsGenericType && method.ReturnType.GetGenericTypeDefinition() == typeof(Task<>)) ||
                             (method.ReturnType.IsGenericType && method.ReturnType.GetGenericTypeDefinition() == typeof(ValueTask<>)))
            .Where(method => !method.Name.EndsWith("Async", StringComparison.Ordinal))
            .Select(method => $"{method.DeclaringType?.FullName}.{method.Name}");

        ArchitectureAssertions.AssertNoViolations(
            violations,
            "Public methods returning Task/ValueTask should end with Async");
    }
}
