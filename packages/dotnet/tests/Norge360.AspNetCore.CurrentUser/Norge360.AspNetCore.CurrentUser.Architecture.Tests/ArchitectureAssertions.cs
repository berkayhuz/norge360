// <copyright file="ArchitectureAssertions.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using System.Reflection;
using System.Runtime.CompilerServices;
using NetArchTest.Rules;

namespace Norge360.AspNetCore.CurrentUser.Architecture.Tests;

internal static class ArchitectureAssertions
{
    internal static IReadOnlyList<Type> GetProductionTypes() =>
        ArchitectureTestAssembly.ProductionAssembly
            .GetTypes()
            .Where(type => !IsCompilerGenerated(type))
            .OrderBy(type => type.FullName, StringComparer.Ordinal)
            .ToArray();

    internal static void AssertRule(TestResult result, string ruleDescription)
    {
        if (result.IsSuccessful)
        {
            return;
        }

        var failingTypes = result.FailingTypes?
            .Select(type => type.FullName ?? type.Name)
            .OrderBy(name => name, StringComparer.Ordinal)
            .ToArray() ?? [];

        Assert.True(
            result.IsSuccessful,
            $"Architecture rule failed: {ruleDescription}.{Environment.NewLine}Violating types:{Environment.NewLine}- {string.Join(Environment.NewLine + "- ", failingTypes)}");
    }

    internal static void AssertNoViolations(IEnumerable<string> violations, string ruleDescription)
    {
        var violatingEntries = violations
            .Distinct(StringComparer.Ordinal)
            .OrderBy(entry => entry, StringComparer.Ordinal)
            .ToArray();

        Assert.True(
            violatingEntries.Length == 0,
            $"Architecture rule failed: {ruleDescription}.{Environment.NewLine}Violations:{Environment.NewLine}- {string.Join(Environment.NewLine + "- ", violatingEntries)}");
    }

    private static bool IsCompilerGenerated(MemberInfo member)
    {
        if (member.IsDefined(typeof(CompilerGeneratedAttribute), inherit: false))
        {
            return true;
        }

        var name = member.Name;
        return name.StartsWith('<') || name.Contains("AnonymousType", StringComparison.Ordinal);
    }
}
