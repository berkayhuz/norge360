// <copyright file="Norge360AwsParameterStoreOptions.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

namespace Norge360.Configuration.AwsParameterStore;

public sealed class Norge360AwsParameterStoreOptions
{
    public const string SectionName = "Infrastructure:AwsParameterStore";

    public bool Enabled { get; set; }

    public bool RequireInProduction { get; set; } = true;

    public bool ReloadOnChange { get; set; }

    public int ReloadAfterSeconds { get; set; } = 300;

    public bool Recursive { get; set; } = true;

    public bool DecryptSecureString { get; set; } = true;

    public bool OptionalWhenEnabled { get; set; }

    public string ParameterPathPrefix { get; set; } = "/norge360/{environment}";

    public string? Region { get; set; }

    public Dictionary<string, string> ParameterNameMappings { get; set; } = new(StringComparer.OrdinalIgnoreCase);

    public List<string> RequiredConfigurationKeys { get; set; } = [];
}
