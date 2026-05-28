// <copyright file="MediaSecurityScanResult.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

namespace Norge360.Media.Models;

public sealed record MediaSecurityScanResult(bool IsSafe, string? FailureReason)
{
    public static MediaSecurityScanResult Safe { get; } = new(true, null);

    public static MediaSecurityScanResult Unsafe(string reason) => new(false, reason);
}
