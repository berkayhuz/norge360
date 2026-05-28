// <copyright file="ArchitectureAssertions.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using System.Reflection;
using System.Runtime.CompilerServices;
using NetArchTest.Rules;

namespace Norge360.Clock.Architecture.Tests;

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

        var failingTypes = result.FailingTypes?.Select(t => t.FullName ?? t.Name).OrderBy(x => x, StringComparer.Ordinal).ToArray() ?? [];
        Assert.True(result.IsSuccessful, $"{ruleDescription}{Environment.NewLine}- {string.Join(Environment.NewLine + "- ", failingTypes)}");
    }

    internal static void AssertNoViolations(IEnumerable<string> violations, string ruleDescription)
    {
        var entries = violations.Distinct(StringComparer.Ordinal).OrderBy(x => x, StringComparer.Ordinal).ToArray();
        Assert.True(entries.Length == 0, $"{ruleDescription}{Environment.NewLine}- {string.Join(Environment.NewLine + "- ", entries)}");
    }

    private static bool IsCompilerGenerated(MemberInfo member) =>
        member.IsDefined(typeof(CompilerGeneratedAttribute), false) || member.Name.StartsWith('<');
}
