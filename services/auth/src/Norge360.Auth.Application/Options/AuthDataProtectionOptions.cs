// <copyright file="AuthDataProtectionOptions.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

namespace Norge360.Auth.Application.Options;

public sealed class AuthDataProtectionOptions
{
    public const string SectionName = "Infrastructure:DataProtection";

    public string ApplicationName { get; set; } = "Norge360.Auth";

    public string? KeyRingPath { get; set; }

    public bool RequirePersistentKeyRingInProduction { get; set; } = true;
}
