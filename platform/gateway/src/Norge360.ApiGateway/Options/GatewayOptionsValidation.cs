// <copyright file="GatewayOptionsValidation.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using System.Text.RegularExpressions;
using Microsoft.Extensions.Options;
using Norge360.AspNetCore.Security;
using Norge360.AspNetCore.TrustedGateway.Options;

namespace Norge360.ApiGateway.Options;

public sealed class GatewayCorsOptionsValidation(IHostEnvironment? environment = null) : IValidateOptions<GatewayCorsOptions>
{
    public ValidateOptionsResult Validate(string? name, GatewayCorsOptions options)
    {
        var failures = new List<string>();
        var allowHttpLoopback = environment?.IsDevelopment() ?? true;

        if (options.AllowedOrigins.Length == 0)
        {
            failures.Add("Security:Cors:AllowedOrigins must contain at least one origin.");
        }

        foreach (var origin in options.AllowedOrigins)
        {
            if (!SecuritySupport.IsValidOrigin(origin, allowHttpForLocalhostOnly: allowHttpLoopback))
            {
                failures.Add($"Security:Cors:AllowedOrigins contains invalid origin '{origin}'.");
            }

            if (environment?.IsProduction() == true &&
                Uri.TryCreate(origin, UriKind.Absolute, out var uri) &&
                uri.IsLoopback)
            {
                failures.Add($"Security:Cors:AllowedOrigins cannot contain loopback origin '{origin}' in production.");
            }
        }

        if (options.AllowCredentials && options.AllowedOrigins.Contains("*", StringComparer.Ordinal))
        {
            failures.Add("Security:Cors:AllowedOrigins cannot contain '*' when credentials are enabled.");
        }

        return failures.Count > 0 ? ValidateOptionsResult.Fail(failures) : ValidateOptionsResult.Success;
    }
}

public sealed class GatewayForwardedHeadersOptionsValidation(IHostEnvironment environment)
    : IValidateOptions<GatewayForwardedHeadersOptions>
{
    public ValidateOptionsResult Validate(string? name, GatewayForwardedHeadersOptions options)
    {
        var failures = new List<string>();

        foreach (var network in options.KnownNetworks)
        {
            if (!SecuritySupport.TryParseNetwork(network, out _))
            {
                failures.Add($"Security:ForwardedHeaders:KnownNetworks contains invalid CIDR '{network}'.");
            }
        }

        foreach (var proxy in options.KnownProxies)
        {
            if (!System.Net.IPAddress.TryParse(proxy, out _))
            {
                failures.Add($"Security:ForwardedHeaders:KnownProxies contains invalid IP '{proxy}'.");
            }
        }

        if (environment.IsProduction() && options.KnownNetworks.Length == 0 && options.KnownProxies.Length == 0)
        {
            failures.Add("Security:ForwardedHeaders must define at least one known proxy or known network in production.");
        }

        return failures.Count > 0 ? ValidateOptionsResult.Fail(failures) : ValidateOptionsResult.Success;
    }
}

public sealed class GatewaySecurityHeadersOptionsValidation : IValidateOptions<GatewaySecurityHeadersOptions>
{
    public ValidateOptionsResult Validate(string? name, GatewaySecurityHeadersOptions options)
    {
        var failures = new List<string>();

        if (string.IsNullOrWhiteSpace(options.ContentSecurityPolicy)) failures.Add("Security:Headers:ContentSecurityPolicy is required.");
        if (string.IsNullOrWhiteSpace(options.ReferrerPolicy)) failures.Add("Security:Headers:ReferrerPolicy is required.");
        if (string.IsNullOrWhiteSpace(options.PermissionsPolicy)) failures.Add("Security:Headers:PermissionsPolicy is required.");

        return failures.Count > 0 ? ValidateOptionsResult.Fail(failures) : ValidateOptionsResult.Success;
    }
}

public sealed class GatewayRateLimitingOptionsValidation : IValidateOptions<GatewayRateLimitingOptions>
{
    public ValidateOptionsResult Validate(string? name, GatewayRateLimitingOptions options)
    {
        var failures = new List<string>();
        ValidateRule(options.Global, "Security:RateLimiting:Global", failures);
        ValidateRule(options.Proxy, "Security:RateLimiting:Proxy", failures);
        return failures.Count > 0 ? ValidateOptionsResult.Fail(failures) : ValidateOptionsResult.Success;
    }

    private static void ValidateRule(FixedWindowRuleOptions rule, string prefix, ICollection<string> failures)
    {
        if (rule.PermitLimit <= 0) failures.Add($"{prefix}:PermitLimit must be greater than 0.");
        if (rule.WindowSeconds <= 0) failures.Add($"{prefix}:WindowSeconds must be greater than 0.");
        if (rule.QueueLimit < 0) failures.Add($"{prefix}:QueueLimit must be 0 or greater.");
    }
}

public sealed partial class GatewayTenantForwardingOptionsValidation(IHostEnvironment environment)
    : IValidateOptions<GatewayTenantForwardingOptions>
{
    private static readonly Guid DefaultDevelopmentTenantId = Guid.Parse("11111111-1111-1111-1111-111111111111");

    public ValidateOptionsResult Validate(string? name, GatewayTenantForwardingOptions options)
    {
        var failures = new List<string>();

        if (string.IsNullOrWhiteSpace(options.HeaderName))
        {
            failures.Add("Security:TenantForwarding:HeaderName is required.");
        }

        if (string.IsNullOrWhiteSpace(options.SlugHeaderName))
        {
            failures.Add("Security:TenantForwarding:SlugHeaderName is required.");
        }

        if (string.IsNullOrWhiteSpace(options.RouteMetadataTenantIdKey))
        {
            failures.Add("Security:TenantForwarding:RouteMetadataTenantIdKey is required.");
        }

        if (string.IsNullOrWhiteSpace(options.RouteMetadataTenantSlugKey))
        {
            failures.Add("Security:TenantForwarding:RouteMetadataTenantSlugKey is required.");
        }

        if (!string.IsNullOrWhiteSpace(options.StaticTenantSlug) &&
            !TenantSlugRegex().IsMatch(options.StaticTenantSlug))
        {
            failures.Add("Security:TenantForwarding:StaticTenantSlug must contain only lowercase letters, numbers and hyphens.");
        }

        foreach (var suffix in options.TrustedHostSuffixes)
        {
            if (!SecuritySupport.LooksLikeHostName(suffix))
            {
                failures.Add($"Security:TenantForwarding:TrustedHostSuffixes contains invalid host suffix '{suffix}'.");
            }

            if (environment.IsProduction() &&
                suffix.Contains("localhost", StringComparison.OrdinalIgnoreCase))
            {
                failures.Add("Security:TenantForwarding:TrustedHostSuffixes cannot contain localhost in production.");
            }
        }

        if (options.RequireTenant &&
            options.StaticTenantId == Guid.Empty &&
            string.IsNullOrWhiteSpace(options.StaticTenantSlug) &&
            options.TrustedHostSuffixes.Length == 0)
        {
            failures.Add("Security:TenantForwarding requires StaticTenantId, StaticTenantSlug or TrustedHostSuffixes.");
        }

        if (environment.IsProduction() && options.StaticTenantId != Guid.Empty)
        {
            if (!options.AllowStaticTenantIdInProduction)
            {
                failures.Add("Security:TenantForwarding:StaticTenantId cannot be used in production unless AllowStaticTenantIdInProduction is explicitly enabled.");
            }

            if (options.StaticTenantId == DefaultDevelopmentTenantId)
            {
                failures.Add("Security:TenantForwarding:StaticTenantId contains the default development tenant id and cannot be used in production.");
            }
        }

        return failures.Count > 0 ? ValidateOptionsResult.Fail(failures) : ValidateOptionsResult.Success;
    }

    [GeneratedRegex("^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$", RegexOptions.CultureInvariant)]
    private static partial Regex TenantSlugRegex();
}

public sealed class GatewayTrustedCallerOptionsValidation(IHostEnvironment environment) : IValidateOptions<TrustedGatewayOptions>
{
    private static readonly string[] UnsafeSecretMarkers = ["REPLACE", "CHANGE_ME", "LOCAL", "DEV", "TEST"];

    public ValidateOptionsResult Validate(string? name, TrustedGatewayOptions options)
    {
        var failures = new List<string>();

        if (string.IsNullOrWhiteSpace(options.Source)) failures.Add("Security:TrustedGateway:Source is required.");
        if (string.IsNullOrWhiteSpace(options.CurrentKeyId)) failures.Add("Security:TrustedGateway:CurrentKeyId is required.");
        if (string.IsNullOrWhiteSpace(options.SignatureHeaderName)) failures.Add("Security:TrustedGateway:SignatureHeaderName is required.");
        if (string.IsNullOrWhiteSpace(options.TimestampHeaderName)) failures.Add("Security:TrustedGateway:TimestampHeaderName is required.");
        if (string.IsNullOrWhiteSpace(options.KeyIdHeaderName)) failures.Add("Security:TrustedGateway:KeyIdHeaderName is required.");
        if (string.IsNullOrWhiteSpace(options.SourceHeaderName)) failures.Add("Security:TrustedGateway:SourceHeaderName is required.");
        if (string.IsNullOrWhiteSpace(options.NonceHeaderName)) failures.Add("Security:TrustedGateway:NonceHeaderName is required.");
        if (string.IsNullOrWhiteSpace(options.ContentHashHeaderName)) failures.Add("Security:TrustedGateway:ContentHashHeaderName is required.");
        if (options.AllowedClockSkewSeconds is < 5 or > 300) failures.Add("Security:TrustedGateway:AllowedClockSkewSeconds must be between 5 and 300.");
        if (options.ReplayProtectionWindowSeconds is < 30 or > 600) failures.Add("Security:TrustedGateway:ReplayProtectionWindowSeconds must be between 30 and 600.");
        if (options.AllowedSources.Length == 0) failures.Add("Security:TrustedGateway:AllowedSources must contain at least one source.");

        if (options.Keys.Count == 0)
        {
            failures.Add("Security:TrustedGateway:Keys must contain at least one key.");
        }
        else
        {
            if (!options.Keys.Any(x => x.Enabled && x.SignRequests && string.Equals(x.KeyId, options.CurrentKeyId, StringComparison.Ordinal)))
            {
                failures.Add("Security:TrustedGateway:CurrentKeyId must point to an enabled signing key.");
            }

            foreach (var key in options.Keys)
            {
                if (string.IsNullOrWhiteSpace(key.KeyId)) failures.Add("Security:TrustedGateway:Keys:KeyId is required.");
                if (string.IsNullOrWhiteSpace(key.Secret)) failures.Add($"Security:TrustedGateway:Keys:{key.KeyId}:Secret is required.");

                if (environment.IsProduction())
                {
                    if ((key.Secret?.Length ?? 0) < 32)
                    {
                        failures.Add($"Security:TrustedGateway:Keys:{key.KeyId}:Secret must be at least 32 characters in production.");
                    }

                    if (!string.IsNullOrWhiteSpace(key.Secret) &&
                        UnsafeSecretMarkers.Any(marker => key.Secret.Contains(marker, StringComparison.OrdinalIgnoreCase)))
                    {
                        failures.Add($"Security:TrustedGateway:Keys:{key.KeyId}:Secret contains a non-production placeholder marker.");
                    }

                    if (!string.IsNullOrWhiteSpace(key.KeyId) &&
                        (key.KeyId.Contains("local", StringComparison.OrdinalIgnoreCase) ||
                         key.KeyId.Contains("dev", StringComparison.OrdinalIgnoreCase) ||
                         key.KeyId.Contains("test", StringComparison.OrdinalIgnoreCase)))
                    {
                        failures.Add($"Security:TrustedGateway:Keys:{key.KeyId}:KeyId cannot be a local/dev/test identifier in production.");
                    }
                }
            }
        }

        return failures.Count > 0 ? ValidateOptionsResult.Fail(failures) : ValidateOptionsResult.Success;
    }
}
