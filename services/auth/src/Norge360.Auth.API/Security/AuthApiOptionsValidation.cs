// <copyright file="AuthApiOptionsValidation.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using Microsoft.Extensions.Options;
using Norge360.AspNetCore.Security;
using Norge360.AspNetCore.TrustedGateway.Options;
using Norge360.Auth.Application.Options;

namespace Norge360.Auth.API.Security;

public sealed class ApiCorsOptionsValidation(IHostEnvironment? environment = null) : IValidateOptions<ApiCorsOptions>
{
    public ValidateOptionsResult Validate(string? name, ApiCorsOptions options)
    {
        var failures = new List<string>();
        var allowHttpLoopback = environment?.IsProduction() != true;

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

public sealed class ApiForwardedHeadersOptionsValidation(IHostEnvironment environment) : IValidateOptions<ApiForwardedHeadersOptions>
{
    public ValidateOptionsResult Validate(string? name, ApiForwardedHeadersOptions options)
    {
        var failures = new List<string>();

        foreach (var proxy in options.KnownProxies)
        {
            if (!System.Net.IPAddress.TryParse(proxy, out _))
            {
                failures.Add($"Security:ForwardedHeaders:KnownProxies contains invalid IP '{proxy}'.");
            }
        }

        foreach (var network in options.KnownNetworks)
        {
            if (!SecuritySupport.TryParseNetwork(network, out _))
            {
                failures.Add($"Security:ForwardedHeaders:KnownNetworks contains invalid CIDR '{network}'.");
            }
        }

        if (environment.IsProduction() && options.KnownProxies.Length == 0 && options.KnownNetworks.Length == 0)
        {
            failures.Add("Security:ForwardedHeaders must define at least one known proxy or network in production.");
        }

        return failures.Count > 0 ? ValidateOptionsResult.Fail(failures) : ValidateOptionsResult.Success;
    }
}

public sealed class ApiSecurityHeadersOptionsValidation : IValidateOptions<ApiSecurityHeadersOptions>
{
    private static readonly string[] RequiredCspDirectives =
    [
        "default-src 'none'",
        "frame-ancestors 'none'",
        "frame-src 'none'",
        "base-uri 'none'",
        "object-src 'none'",
        "form-action 'none'"
    ];

    public ValidateOptionsResult Validate(string? name, ApiSecurityHeadersOptions options)
    {
        var failures = new List<string>();
        if (string.IsNullOrWhiteSpace(options.ContentSecurityPolicy))
        {
            failures.Add("Security:Headers:ContentSecurityPolicy is required.");
        }
        else
        {
            foreach (var directive in RequiredCspDirectives)
            {
                if (!options.ContentSecurityPolicy.Contains(directive, StringComparison.OrdinalIgnoreCase))
                {
                    failures.Add($"Security:Headers:ContentSecurityPolicy must include {directive}.");
                }
            }
        }

        if (string.IsNullOrWhiteSpace(options.ReferrerPolicy)) failures.Add("Security:Headers:ReferrerPolicy is required.");
        if (string.IsNullOrWhiteSpace(options.PermissionsPolicy)) failures.Add("Security:Headers:PermissionsPolicy is required.");
        return failures.Count > 0 ? ValidateOptionsResult.Fail(failures) : ValidateOptionsResult.Success;
    }
}

public sealed class TenantResolutionOptionsValidation(IHostEnvironment environment) : IValidateOptions<TenantResolutionOptions>
{
    public ValidateOptionsResult Validate(string? name, TenantResolutionOptions options)
    {
        var failures = new List<string>();

        if (string.IsNullOrWhiteSpace(options.HeaderName))
        {
            failures.Add("Security:TenantResolution:HeaderName is required.");
        }

        if (string.IsNullOrWhiteSpace(options.SlugHeaderName))
        {
            failures.Add("Security:TenantResolution:SlugHeaderName is required.");
        }

        foreach (var prefix in options.TenantOptionalPathPrefixes)
        {
            if (string.IsNullOrWhiteSpace(prefix) || !prefix.StartsWith('/'))
            {
                failures.Add("Security:TenantResolution:TenantOptionalPathPrefixes entries must be absolute application paths.");
                break;
            }
        }

        if (environment.IsProduction())
        {
            if (options.AllowBodyFallback)
            {
                failures.Add("Security:TenantResolution:AllowBodyFallback must be false in production.");
            }

            if (!options.RequireResolvedTenant)
            {
                failures.Add("Security:TenantResolution:RequireResolvedTenant must be true in production.");
            }

            if (options.TrustedHostSuffixes.Any(x => x.Contains("localhost", StringComparison.OrdinalIgnoreCase)))
            {
                failures.Add("Security:TenantResolution:TrustedHostSuffixes cannot contain localhost in production.");
            }
        }

        return failures.Count > 0 ? ValidateOptionsResult.Fail(failures) : ValidateOptionsResult.Success;
    }
}

public sealed class AuthRateLimitingOptionsValidation : IValidateOptions<AuthRateLimitingOptions>
{
    public ValidateOptionsResult Validate(string? name, AuthRateLimitingOptions options)
    {
        var failures = new List<string>();
        ValidateRule(options.Global, "Security:RateLimiting:Global", failures);
        ValidateRule(options.Login, "Security:RateLimiting:Login", failures);
        ValidateRule(options.Register, "Security:RateLimiting:Register", failures);
        ValidateRule(options.Refresh, "Security:RateLimiting:Refresh", failures);
        ValidateRule(options.Logout, "Security:RateLimiting:Logout", failures);
        ValidateRule(options.Invite, "Security:RateLimiting:Invite", failures);
        ValidateRule(options.RoleManagement, "Security:RateLimiting:RoleManagement", failures);
        ValidateRule(options.PasswordRecovery, "Security:RateLimiting:PasswordRecovery", failures);
        ValidateRule(options.EmailConfirmation, "Security:RateLimiting:EmailConfirmation", failures);
        return failures.Count > 0 ? ValidateOptionsResult.Fail(failures) : ValidateOptionsResult.Success;
    }

    private static void ValidateRule(FixedWindowRuleOptions rule, string prefix, ICollection<string> failures)
    {
        if (rule.PermitLimit <= 0) failures.Add($"{prefix}:PermitLimit must be greater than 0.");
        if (rule.WindowSeconds <= 0) failures.Add($"{prefix}:WindowSeconds must be greater than 0.");
        if (rule.QueueLimit < 0) failures.Add($"{prefix}:QueueLimit must be 0 or greater.");
    }
}

public sealed class TokenTransportOptionsValidation(IHostEnvironment environment) : IValidateOptions<TokenTransportOptions>
{
    public ValidateOptionsResult Validate(string? name, TokenTransportOptions options)
    {
        var failures = new List<string>();

        if (!string.Equals(options.Mode, TokenTransportModes.CookiesOnly, StringComparison.OrdinalIgnoreCase) &&
            !string.Equals(options.Mode, TokenTransportModes.BodyOnly, StringComparison.OrdinalIgnoreCase) &&
            !string.Equals(options.Mode, TokenTransportModes.HybridDevelopment, StringComparison.OrdinalIgnoreCase))
        {
            failures.Add("Security:TokenTransport:Mode must be CookiesOnly, BodyOnly or HybridDevelopment.");
        }

        if (!environment.IsDevelopment() && !string.Equals(options.Mode, TokenTransportModes.CookiesOnly, StringComparison.OrdinalIgnoreCase))
        {
            failures.Add("Security:TokenTransport:Mode must be CookiesOnly outside development.");
        }

        if (!environment.IsDevelopment() && options.AllowRefreshTokenFromRequestBody)
        {
            failures.Add("Security:TokenTransport:AllowRefreshTokenFromRequestBody is not allowed outside development.");
        }

        if (!environment.IsDevelopment() && options.AllowSessionIdFromRequestBody)
        {
            failures.Add("Security:TokenTransport:AllowSessionIdFromRequestBody is not allowed outside development.");
        }

        ValidateCookie(options.AccessCookieName, options.AccessCookiePath, "AccessCookie", failures);
        ValidateCookie(options.RefreshCookieName, options.RefreshCookiePath, "RefreshCookie", failures);
        ValidateCookie(options.SessionCookieName, options.SessionCookiePath, "SessionCookie", failures);

        if (!environment.IsDevelopment())
        {
            ValidateSecurePrefix(options.AccessCookieName, "AccessCookieName", failures);
            ValidateSecurePrefix(options.RefreshCookieName, "RefreshCookieName", failures);
            ValidateSecurePrefix(options.SessionCookieName, "SessionCookieName", failures);
        }

        if (!IsValidCookieDomain(options.CookieDomain))
        {
            failures.Add("Security:TokenTransport:CookieDomain must be a host name without scheme or path.");
        }

        ValidateHostCookieDomain(options.AccessCookieName, "AccessCookieName", options.CookieDomain, failures);
        ValidateHostCookieDomain(options.RefreshCookieName, "RefreshCookieName", options.CookieDomain, failures);
        ValidateHostCookieDomain(options.SessionCookieName, "SessionCookieName", options.CookieDomain, failures);

        if (!IsKnownSameSite(options.SameSite))
        {
            failures.Add("Security:TokenTransport:SameSite must be Strict, Lax or None.");
        }

        return failures.Count > 0 ? ValidateOptionsResult.Fail(failures) : ValidateOptionsResult.Success;
    }

    private static void ValidateCookie(string cookieName, string path, string label, ICollection<string> failures)
    {
        if (string.IsNullOrWhiteSpace(cookieName)) failures.Add($"Security:TokenTransport:{label}Name is required.");
        if (string.IsNullOrWhiteSpace(path) || !path.StartsWith('/')) failures.Add($"Security:TokenTransport:{label}Path must start with '/'.");

        if (cookieName.StartsWith("__Host-", StringComparison.Ordinal))
        {
            if (path != "/") failures.Add($"Security:TokenTransport:{label}Path must be '/' for __Host- cookies.");
        }
    }

    private static void ValidateSecurePrefix(string cookieName, string settingName, ICollection<string> failures)
    {
        if (cookieName.StartsWith("__Secure-", StringComparison.Ordinal) ||
            cookieName.StartsWith("__Host-", StringComparison.Ordinal))
        {
            return;
        }

        failures.Add($"Security:TokenTransport:{settingName} must start with __Secure- or __Host- outside development.");
    }

    private static void ValidateHostCookieDomain(string cookieName, string settingName, string? cookieDomain, ICollection<string> failures)
    {
        if (!string.IsNullOrWhiteSpace(cookieDomain) && cookieName.StartsWith("__Host-", StringComparison.Ordinal))
        {
            failures.Add($"Security:TokenTransport:{settingName} cannot use __Host- when CookieDomain is configured.");
        }
    }

    private static bool IsValidCookieDomain(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return true;
        }

        return SecuritySupport.LooksLikeHostName(value.TrimStart('.'));
    }

    private static bool IsKnownSameSite(string value) =>
        value.Equals("Strict", StringComparison.OrdinalIgnoreCase) ||
        value.Equals("Lax", StringComparison.OrdinalIgnoreCase) ||
        value.Equals("None", StringComparison.OrdinalIgnoreCase);
}

public sealed class AuthTrustedGatewayOptionsValidation(IHostEnvironment environment) : IValidateOptions<TrustedGatewayOptions>
{
    private static readonly string[] UnsafeSecretMarkers = ["REPLACE", "CHANGE_ME", "LOCAL", "DEV", "TEST"];

    public ValidateOptionsResult Validate(string? name, TrustedGatewayOptions options)
    {
        var failures = new List<string>();

        if (options.RequireTrustedGateway)
        {
            if (options.Keys.Count == 0) failures.Add("Security:TrustedGateway:Keys must contain at least one key.");
            if (options.AllowedSources.Length == 0) failures.Add("Security:TrustedGateway:AllowedSources must contain at least one source.");
            if (options.AllowedClockSkewSeconds is < 5 or > 300) failures.Add("Security:TrustedGateway:AllowedClockSkewSeconds must be between 5 and 300.");
            if (options.ReplayProtectionWindowSeconds is < 30 or > 600) failures.Add("Security:TrustedGateway:ReplayProtectionWindowSeconds must be between 30 and 600.");

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

            if (environment.IsProduction() && options.AllowedGatewayProxies.Length == 0 && options.AllowedGatewayNetworks.Length == 0)
            {
                failures.Add("Security:TrustedGateway must define at least one allowed gateway proxy or network in production.");
            }

            foreach (var proxy in options.AllowedGatewayProxies)
            {
                if (!System.Net.IPAddress.TryParse(proxy, out _))
                {
                    failures.Add($"Security:TrustedGateway:AllowedGatewayProxies contains invalid IP '{proxy}'.");
                }
            }

            foreach (var network in options.AllowedGatewayNetworks)
            {
                if (!SecuritySupport.TryParseNetwork(network, out _))
                {
                    failures.Add($"Security:TrustedGateway:AllowedGatewayNetworks contains invalid CIDR '{network}'.");
                }
            }
        }

        return failures.Count > 0 ? ValidateOptionsResult.Fail(failures) : ValidateOptionsResult.Success;
    }
}
