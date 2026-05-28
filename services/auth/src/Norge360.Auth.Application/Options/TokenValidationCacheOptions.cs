// <copyright file="TokenValidationCacheOptions.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

namespace Norge360.Auth.Application.Options;

public sealed class TokenValidationCacheOptions
{
    public const string SectionName = "Security:TokenValidationCache";

    public bool EnableCache { get; set; } = true;

    // Upper bound for valid-cache stale authorization/session state when explicit eviction is unavailable.
    public int AbsoluteExpirationSeconds { get; set; } = 15;

    public int NegativeAbsoluteExpirationSeconds { get; set; } = 10;

    public string KeyPrefix { get; set; } = "auth:user-token-state";
}
