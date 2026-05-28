// <copyright file="PublicApiBaselineTests.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

namespace Norge360.AspNetCore.Architecture.Tests;

public class PublicApiBaselineTests
{
    [Fact]
    public void Public_api_should_match_the_approved_baseline()
    {
        AssertBaselineMatches("PublicApiBaseline.txt", strictMode: false);
    }

    [Fact]
    public void Strict_public_api_should_match_the_approved_baseline_when_enabled()
    {
        var strictModeEnabled = string.Equals(
            Environment.GetEnvironmentVariable("N360_API_BASELINE_STRICT"),
            "true",
            StringComparison.OrdinalIgnoreCase);

        if (!strictModeEnabled)
        {
            return;
        }

        AssertBaselineMatches("PublicApiBaseline.Strict.txt", strictMode: true);
    }

    private static void AssertBaselineMatches(string baselineFileName, bool strictMode)
    {
        var baselinePath = Path.Combine(AppContext.BaseDirectory, baselineFileName);
        var expected = File.ReadAllLines(baselinePath)
            .Where(line => !string.IsNullOrWhiteSpace(line))
            .ToArray();
        var actual = PublicApiSignatureGenerator.GeneratePublicApiBaselineLines(strictMode);

        var missing = expected.Except(actual, StringComparer.Ordinal).OrderBy(x => x, StringComparer.Ordinal).ToArray();
        var added = actual.Except(expected, StringComparer.Ordinal).OrderBy(x => x, StringComparer.Ordinal).ToArray();

        var isMatch = missing.Length == 0 && added.Length == 0;
        Assert.True(isMatch, BuildFailureMessage(baselineFileName, missing, added));
    }

    private static string BuildFailureMessage(string baselineFileName, IReadOnlyList<string> missing, IReadOnlyList<string> added)
    {
        var lines = new List<string>
        {
            "Public API baseline mismatch detected.",
            $"If this change is intentional, update {baselineFileName} in the architecture test project.",
            string.Empty,
            "Missing entries (in baseline but not in current API):"
        };

        lines.AddRange(missing.Count == 0 ? ["- <none>"] : missing.Select(x => $"- {x}"));
        lines.Add(string.Empty);
        lines.Add("Added entries (in current API but not in baseline):");
        lines.AddRange(added.Count == 0 ? ["- <none>"] : added.Select(x => $"- {x}"));

        return string.Join(Environment.NewLine, lines);
    }
}
