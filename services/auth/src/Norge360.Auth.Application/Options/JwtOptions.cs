// <copyright file="JwtOptions.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

namespace Norge360.Auth.Application.Options;

public sealed class JwtOptions
{
    public const string SectionName = "Jwt";

    public string Issuer { get; set; } = null!;
    public string Audience { get; set; } = null!;
    public int AccessTokenMinutes { get; set; } = 15;
    public int RefreshTokenHours { get; set; } = 8;
    public int RefreshTokenPersistentDays { get; set; } = 14;
    public JwtSigningKeyOptions[] SigningKeys { get; set; } = [];
}

public sealed class JwtSigningKeyOptions
{
    public string KeyId { get; set; } = null!;
    public bool IsCurrent { get; set; }
    public string? PrivateKeyPath { get; set; }
    public string PrivateKeyPem { get; set; } = null!;
}
