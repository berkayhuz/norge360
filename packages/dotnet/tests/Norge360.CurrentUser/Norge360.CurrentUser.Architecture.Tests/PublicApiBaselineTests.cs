// <copyright file="PublicApiBaselineTests.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

namespace Norge360.CurrentUser.Architecture.Tests;

public class PublicApiBaselineTests
{
    [Fact]
    public void Public_api_should_match_the_approved_baseline()
    {
        AssertBaselineMatches("PublicApiBaseline.txt", strictMode: false);
    }

    private static void AssertBaselineMatches(string baselineFileName, bool strictMode)
    {
        var baselinePath = Path.Combine(AppContext.BaseDirectory, baselineFileName);
        var expected = File.ReadAllLines(baselinePath).Where(line => !string.IsNullOrWhiteSpace(line)).Select(Normalize).ToArray();
        var actual = PublicApiSignatureGenerator.GeneratePublicApiBaselineLines(strictMode).Select(Normalize).ToArray();

        var missing = expected.Except(actual, StringComparer.Ordinal).OrderBy(x => x, StringComparer.Ordinal).ToArray();
        var added = actual.Except(expected, StringComparer.Ordinal).OrderBy(x => x, StringComparer.Ordinal).ToArray();
        Assert.True(missing.Length == 0 && added.Length == 0, BuildFailureMessage(baselineFileName, missing, added));
    }

    private static string Normalize(string line) => line.Trim();

    private static string BuildFailureMessage(string baselineFileName, IReadOnlyList<string> missing, IReadOnlyList<string> added)
    {
        var lines = new List<string>
        {
            "Public API baseline mismatch detected.",
            $"If intentional, update {baselineFileName}.",
            string.Empty,
            "Missing entries:"
        };

        lines.AddRange(missing.Count == 0 ? ["- <none>"] : missing.Select(x => $"- {x}"));
        lines.Add(string.Empty);
        lines.Add("Added entries:");
        lines.AddRange(added.Count == 0 ? ["- <none>"] : added.Select(x => $"- {x}"));
        return string.Join(Environment.NewLine, lines);
    }
}
