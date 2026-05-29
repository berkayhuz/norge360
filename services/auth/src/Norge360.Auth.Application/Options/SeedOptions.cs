// <copyright file="SeedOptions.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

namespace Norge360.Auth.Application.Options;

public sealed class SeedOptions
{
    public const string SectionName = "Seed";

    public bool AllowStartupSeed { get; set; }

    public bool AllowProductionStartupSeed { get; set; }
}
