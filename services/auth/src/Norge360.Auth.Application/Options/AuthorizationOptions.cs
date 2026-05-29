// <copyright file="AuthorizationOptions.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

namespace Norge360.Auth.Application.Options;

using Microsoft.Extensions.Options;

public sealed class AuthorizationOptions
{
    public const string SectionName = "Authorization";

    public string[] DefaultPermissions { get; set; } =
    [
        "session:self",
        "profile:self"
    ];

    public string[] BootstrapFirstUserPermissions { get; set; } =
    [
        "*"
    ];

    public PolicyDefinition[] Policies { get; set; } = [];
}

public sealed class PolicyDefinition
{
    public string Name { get; set; } = null!;

    public string[] RequiredPermissions { get; set; } = [];

    public string[] RequiredRoles { get; set; } = [];

    public bool RequireAuthenticatedUser { get; set; } = true;
}

public sealed class AuthorizationOptionsValidation : IValidateOptions<AuthorizationOptions>
{
    private const int RolesColumnMaxLength = 512;
    private const int PermissionsColumnMaxLength = 2048;

    public ValidateOptionsResult Validate(string? name, AuthorizationOptions options)
    {
        var failures = new List<string>();

        ValidatePrincipalSet(options.DefaultPermissions, "Authorization:DefaultPermissions", PermissionsColumnMaxLength, allowWildcard: true, failures);
        ValidatePrincipalSet(options.BootstrapFirstUserPermissions, "Authorization:BootstrapFirstUserPermissions", PermissionsColumnMaxLength, allowWildcard: true, failures);

        var policyNames = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var policy in options.Policies)
        {
            if (string.IsNullOrWhiteSpace(policy.Name))
            {
                failures.Add("Authorization:Policies:Name is required.");
                continue;
            }

            if (!policyNames.Add(policy.Name))
            {
                failures.Add($"Authorization:Policies contains duplicate policy '{policy.Name}'.");
            }

            ValidatePrincipalSet(policy.RequiredRoles, $"Authorization:Policies:{policy.Name}:RequiredRoles", RolesColumnMaxLength, allowWildcard: false, failures);
            ValidatePrincipalSet(policy.RequiredPermissions, $"Authorization:Policies:{policy.Name}:RequiredPermissions", PermissionsColumnMaxLength, allowWildcard: true, failures);
        }

        return failures.Count == 0
            ? ValidateOptionsResult.Success
            : ValidateOptionsResult.Fail(failures);
    }

    private static void ValidatePrincipalSet(
        IReadOnlyCollection<string> values,
        string prefix,
        int maxJoinedLength,
        bool allowWildcard,
        ICollection<string> failures)
    {
        if (values.Any(string.IsNullOrWhiteSpace))
        {
            failures.Add($"{prefix} cannot contain empty values.");
        }

        if (!allowWildcard && values.Any(value => string.Equals(value, "*", StringComparison.Ordinal)))
        {
            failures.Add($"{prefix} cannot contain wildcard '*'.");
        }

        var joinedLength = string.Join(',', values).Length;
        if (joinedLength > maxJoinedLength)
        {
            failures.Add($"{prefix} serialized length must be {maxJoinedLength} characters or fewer.");
        }
    }
}
