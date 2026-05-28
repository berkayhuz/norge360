// <copyright file="AuthOptionValidation.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Options;
using Norge360.AspNetCore.Security;
using Norge360.AspNetCore.TrustedGateway.Options;
using Norge360.Auth.Application.Options;

namespace Norge360.Auth.Infrastructure.DependencyInjection;

internal sealed class JwtOptionsValidation(IHostEnvironment environment) : IValidateOptions<JwtOptions>
{
    public ValidateOptionsResult Validate(string? name, JwtOptions options)
    {
        var failures = new List<string>();

        if (!Uri.TryCreate(options.Issuer, UriKind.Absolute, out var issuerUri) ||
            (issuerUri.Scheme != Uri.UriSchemeHttps && !IsDevelopmentHttpLoopback(issuerUri)))
        {
            failures.Add("Jwt:Issuer must be an absolute HTTPS URL.");
        }
        else if (environment.IsProduction() && IsLocalhost(issuerUri))
        {
            failures.Add("Jwt:Issuer cannot point to localhost in production.");
        }

        if (!Uri.TryCreate(options.Audience, UriKind.Absolute, out var audienceUri) ||
            (audienceUri.Scheme != Uri.UriSchemeHttps && !IsDevelopmentHttpLoopback(audienceUri)))
        {
            failures.Add("Jwt:Audience must be an absolute HTTPS URL.");
        }
        else if (environment.IsProduction() && IsLocalhost(audienceUri))
        {
            failures.Add("Jwt:Audience cannot point to localhost in production.");
        }

        if (options.AccessTokenMinutes is < 1 or > 1440)
        {
            failures.Add("Jwt:AccessTokenMinutes must be between 1 and 1440.");
        }

        if (options.RefreshTokenHours is < 1 or > 168)
        {
            failures.Add("Jwt:RefreshTokenHours must be between 1 and 168.");
        }

        if (options.RefreshTokenPersistentDays is < 1 or > 90)
        {
            failures.Add("Jwt:RefreshTokenPersistentDays must be between 1 and 90.");
        }

        if (options.SigningKeys.Length == 0 && !environment.IsDevelopment())
        {
            failures.Add("Jwt:SigningKeys must contain at least one PEM-encoded RSA private key.");
        }

        if (options.SigningKeys.Length > 0 && options.SigningKeys.Count(x => x.IsCurrent) != 1)
        {
            failures.Add("Jwt:SigningKeys must mark exactly one key as current.");
        }

        foreach (var key in options.SigningKeys)
        {
            if (string.IsNullOrWhiteSpace(key.KeyId))
            {
                failures.Add("Jwt:SigningKeys:KeyId is required.");
            }

            var hasPem = !string.IsNullOrWhiteSpace(key.PrivateKeyPem) && key.PrivateKeyPem.Contains("BEGIN", StringComparison.Ordinal);
            var hasPath = !string.IsNullOrWhiteSpace(key.PrivateKeyPath);
            if (!hasPem && !hasPath)
            {
                failures.Add($"Jwt signing key '{key.KeyId}' must define a PEM-encoded RSA private key or a private key path.");
            }

            if (environment.IsProduction())
            {
                if (key.KeyId.Contains("local", StringComparison.OrdinalIgnoreCase) ||
                    key.KeyId.Contains("dev", StringComparison.OrdinalIgnoreCase))
                {
                    failures.Add($"Jwt signing key '{key.KeyId}' cannot use a local/dev key id in production.");
                }

                if (!string.IsNullOrWhiteSpace(key.PrivateKeyPath) &&
                    key.PrivateKeyPath.Contains("dev-", StringComparison.OrdinalIgnoreCase))
                {
                    failures.Add($"Jwt signing key '{key.KeyId}' cannot use a dev private key path in production.");
                }
            }
        }

        return failures.Count > 0
            ? ValidateOptionsResult.Fail(failures)
            : ValidateOptionsResult.Success;
    }

    private static bool IsLocalhost(Uri uri) =>
        uri.IsLoopback ||
        uri.Host.Equals("localhost", StringComparison.OrdinalIgnoreCase);

    private bool IsDevelopmentHttpLoopback(Uri uri) =>
        environment.IsDevelopment() &&
        uri.Scheme == Uri.UriSchemeHttp &&
        IsLocalhost(uri);
}

internal sealed class IdentitySecurityOptionsValidation : IValidateOptions<IdentitySecurityOptions>
{
    private readonly IHostEnvironment environment;

    public IdentitySecurityOptionsValidation(IHostEnvironment environment)
    {
        this.environment = environment;
    }

    public ValidateOptionsResult Validate(string? name, IdentitySecurityOptions options)
    {
        var failures = new List<string>();

        if (environment.IsDevelopment() &&
            options.MaxFailedAccessAttempts == 0 &&
            options.LockoutMinutes == 0)
        {
            return ValidateOptionsResult.Success;
        }

        if (options.MaxFailedAccessAttempts is < 3 or > 20)
        {
            failures.Add("IdentitySecurity:MaxFailedAccessAttempts must be between 3 and 20.");
        }

        if (options.LockoutMinutes is < 1 or > 1440)
        {
            failures.Add("IdentitySecurity:LockoutMinutes must be between 1 and 1440.");
        }

        return failures.Count > 0
            ? ValidateOptionsResult.Fail(failures)
            : ValidateOptionsResult.Success;
    }
}

internal sealed class AccountLifecycleOptionsValidation(IHostEnvironment environment) : IValidateOptions<AccountLifecycleOptions>
{
    public ValidateOptionsResult Validate(string? name, AccountLifecycleOptions options)
    {
        var failures = new List<string>();

        if (options.EmailConfirmationTokenMinutes is < 5 or > 10080)
        {
            failures.Add("AccountLifecycle:EmailConfirmationTokenMinutes must be between 5 minutes and 7 days.");
        }

        if (options.PasswordResetTokenMinutes is < 5 or > 1440)
        {
            failures.Add("AccountLifecycle:PasswordResetTokenMinutes must be between 5 minutes and 24 hours.");
        }

        if (options.PasswordResetCooldownSeconds is < 10 or > 3600)
        {
            failures.Add("AccountLifecycle:PasswordResetCooldownSeconds must be between 10 seconds and 1 hour.");
        }

        if (options.EmailChangeTokenMinutes is < 5 or > 1440)
        {
            failures.Add("AccountLifecycle:EmailChangeTokenMinutes must be between 5 minutes and 24 hours.");
        }

        if (options.EmailConfirmationResendCooldownSeconds is < 10 or > 3600)
        {
            failures.Add("AccountLifecycle:EmailConfirmationResendCooldownSeconds must be between 10 seconds and 1 hour.");
        }

        if (options.InvitationTokenMinutes is < 5 or > 43200)
        {
            failures.Add("AccountLifecycle:InvitationTokenMinutes must be between 5 minutes and 30 days.");
        }

        if (options.TokenBytes < 32)
        {
            failures.Add("AccountLifecycle:TokenBytes must be at least 32.");
        }

        if (!Uri.TryCreate(options.PublicAppBaseUrl, UriKind.Absolute, out var publicBaseUri) ||
            (publicBaseUri.Scheme != Uri.UriSchemeHttps && !(environment.IsDevelopment() && publicBaseUri.IsLoopback && publicBaseUri.Scheme == Uri.UriSchemeHttp)))
        {
            failures.Add("AccountLifecycle:PublicAppBaseUrl must be an absolute HTTPS URL, except HTTP loopback in Development.");
        }
        else if (environment.IsProduction() && IsUnsafeProductionUri(publicBaseUri))
        {
            failures.Add("AccountLifecycle:PublicAppBaseUrl must be a production HTTPS URL.");
        }

        ValidatePath(options.ConfirmEmailPath, "AccountLifecycle:ConfirmEmailPath", failures);
        ValidatePath(options.ResetPasswordPath, "AccountLifecycle:ResetPasswordPath", failures);
        ValidatePath(options.ConfirmEmailChangePath, "AccountLifecycle:ConfirmEmailChangePath", failures);

        return failures.Count > 0
            ? ValidateOptionsResult.Fail(failures)
            : ValidateOptionsResult.Success;
    }

    private static void ValidatePath(string path, string settingName, ICollection<string> failures)
    {
        if (string.IsNullOrWhiteSpace(path) || !path.StartsWith('/'))
        {
            failures.Add($"{settingName} must be an absolute application path.");
        }
    }

    private static bool IsUnsafeProductionUri(Uri uri) =>
        uri.Scheme != Uri.UriSchemeHttps ||
        uri.IsLoopback ||
        ContainsUnsafeMarker(uri.Host);

    private static bool ContainsUnsafeMarker(string value)
    {
        var markers = new[] { "localhost", "127.0.0.1", "::1", "change_me", "replace", "local", "dev", "test" };
        return markers.Any(marker => value.Contains(marker, StringComparison.OrdinalIgnoreCase));
    }
}

internal sealed class InvitationDeliveryOptionsValidation(IHostEnvironment environment) : IValidateOptions<InvitationDeliveryOptions>
{
    public ValidateOptionsResult Validate(string? name, InvitationDeliveryOptions options)
    {
        var failures = new List<string>();

        if (!Uri.TryCreate(options.AcceptBaseUrl, UriKind.Absolute, out var baseUri) ||
            (baseUri.Scheme != Uri.UriSchemeHttps && !(environment.IsDevelopment() && baseUri.IsLoopback && baseUri.Scheme == Uri.UriSchemeHttp)))
        {
            failures.Add("InvitationDelivery:AcceptBaseUrl must be an absolute HTTPS URL, except HTTP loopback in Development.");
        }
        else if (environment.IsProduction() && baseUri.IsLoopback)
        {
            failures.Add("InvitationDelivery:AcceptBaseUrl cannot point to localhost in production.");
        }
        else if (environment.IsProduction() && IsUnsafeProductionUri(baseUri))
        {
            failures.Add("InvitationDelivery:AcceptBaseUrl must be a production HTTPS URL.");
        }

        if (string.IsNullOrWhiteSpace(options.AcceptPath))
        {
            failures.Add("InvitationDelivery:AcceptPath is required.");
        }

        if (string.IsNullOrWhiteSpace(options.SenderName))
        {
            failures.Add("InvitationDelivery:SenderName is required.");
        }

        if (string.IsNullOrWhiteSpace(options.SenderAddress) || !options.SenderAddress.Contains('@', StringComparison.Ordinal))
        {
            failures.Add("InvitationDelivery:SenderAddress must be a valid sender email address.");
        }

        if (environment.IsProduction())
        {
            if (options.DisableDelivery)
            {
                failures.Add("InvitationDelivery:DisableDelivery must be false in production.");
            }

            if (ContainsUnsafeMarker(options.SenderAddress) || ContainsUnsafeMarker(options.SenderName))
            {
                failures.Add("InvitationDelivery sender settings must not contain local/dev/test markers in production.");
            }
        }

        if (!options.DisableDelivery)
        {
            var usesSmtp = string.Equals(options.Provider, "smtp", StringComparison.OrdinalIgnoreCase);
            var usesNotificationPipeline = string.Equals(options.Provider, "notification", StringComparison.OrdinalIgnoreCase) ||
                                           string.Equals(options.Provider, "outbox", StringComparison.OrdinalIgnoreCase);
            if (!usesSmtp && !usesNotificationPipeline)
            {
                failures.Add("InvitationDelivery:Provider must be either 'notification' (recommended) or 'smtp' when delivery is enabled.");
            }

            if (usesSmtp)
            {
                if (string.IsNullOrWhiteSpace(options.SmtpHost))
                {
                    failures.Add("InvitationDelivery:SmtpHost is required when SMTP delivery is enabled.");
                }

                if (options.SmtpPort is < 1 or > 65535)
                {
                    failures.Add("InvitationDelivery:SmtpPort must be a valid TCP port.");
                }

                if (!string.IsNullOrWhiteSpace(options.SmtpUserName) && string.IsNullOrWhiteSpace(options.SmtpPassword))
                {
                    failures.Add("InvitationDelivery:SmtpPassword is required when SmtpUserName is configured.");
                }
            }

            if (environment.IsProduction())
            {
                if (usesSmtp)
                {
                    failures.Add("InvitationDelivery:Provider must be 'notification' in production so invite delivery stays decoupled from Auth.");

                    if (IsUnsafeProductionHost(options.SmtpHost))
                    {
                        failures.Add("InvitationDelivery:SmtpHost must be a production SMTP host.");
                    }

                    if (!options.SmtpUseStartTls)
                    {
                        failures.Add("InvitationDelivery:SmtpUseStartTls must be true in production.");
                    }

                    if (string.IsNullOrWhiteSpace(options.SmtpUserName) || string.IsNullOrWhiteSpace(options.SmtpPassword))
                    {
                        failures.Add("InvitationDelivery SMTP credentials are required in production.");
                    }

                    if (!string.IsNullOrWhiteSpace(options.SmtpPassword) &&
                        (options.SmtpPassword.Length < 16 || ContainsUnsafeMarker(options.SmtpPassword)))
                    {
                        failures.Add("InvitationDelivery:SmtpPassword must be a strong production secret.");
                    }

                    if (ContainsUnsafeMarker(options.SmtpUserName ?? string.Empty))
                    {
                        failures.Add("InvitationDelivery:SmtpUserName must not contain local/dev/test markers in production.");
                    }
                }
            }
        }

        if (options.ResendThrottleSeconds is < 10 or > 86400)
        {
            failures.Add("InvitationDelivery:ResendThrottleSeconds must be between 10 seconds and 24 hours.");
        }

        if (options.MaxResends is < 0 or > 20)
        {
            failures.Add("InvitationDelivery:MaxResends must be between 0 and 20.");
        }

        return failures.Count > 0
            ? ValidateOptionsResult.Fail(failures)
            : ValidateOptionsResult.Success;
    }

    private static bool IsUnsafeProductionUri(Uri uri) =>
        uri.Scheme != Uri.UriSchemeHttps ||
        uri.IsLoopback ||
        ContainsUnsafeMarker(uri.Host);

    private static bool IsUnsafeProductionHost(string? host) =>
        string.IsNullOrWhiteSpace(host) ||
        Uri.CheckHostName(host) == UriHostNameType.Unknown ||
        ContainsUnsafeMarker(host);

    private static bool ContainsUnsafeMarker(string value)
    {
        var markers = new[] { "localhost", "127.0.0.1", "::1", "change_me", "replace", "local", "dev", "test" };
        return markers.Any(marker => value.Contains(marker, StringComparison.OrdinalIgnoreCase));
    }
}

internal sealed class PasswordPolicyOptionsValidation : IValidateOptions<PasswordPolicyOptions>
{
    public ValidateOptionsResult Validate(string? name, PasswordPolicyOptions options)
    {
        var failures = new List<string>();

        if (options.MinimumLength < 8)
        {
            failures.Add("PasswordPolicy:MinimumLength must be at least 8.");
        }

        if (options.MaxLength < options.MinimumLength)
        {
            failures.Add("PasswordPolicy:MaxLength must be greater than or equal to MinimumLength.");
        }

        if (options.RequiredUniqueChars < 1)
        {
            failures.Add("PasswordPolicy:RequiredUniqueChars must be at least 1.");
        }

        return failures.Count > 0
            ? ValidateOptionsResult.Fail(failures)
            : ValidateOptionsResult.Success;
    }
}

internal sealed class DatabaseOptionsValidation(IHostEnvironment environment, IConfiguration configuration) : IValidateOptions<DatabaseOptions>
{
    public ValidateOptionsResult Validate(string? name, DatabaseOptions options)
    {
        var failures = new List<string>();

        if (environment.IsProduction())
        {
            if (options.ApplyMigrationsOnStartup)
            {
                failures.Add("Database:ApplyMigrationsOnStartup must be false in production.");
            }

            var connectionString = configuration.GetConnectionString("IdentityConnection");
            if (string.IsNullOrWhiteSpace(connectionString))
            {
                failures.Add("ConnectionStrings:IdentityConnection is required.");
            }
            else
            {
                if (connectionString.Contains("localhost", StringComparison.OrdinalIgnoreCase) ||
                    connectionString.Contains("127.0.0.1", StringComparison.OrdinalIgnoreCase) ||
                    connectionString.Contains("(local)", StringComparison.OrdinalIgnoreCase))
                {
                    failures.Add("ConnectionStrings:IdentityConnection cannot point to localhost in production.");
                }

                if (!connectionString.Contains("SSL Mode=Require", StringComparison.OrdinalIgnoreCase) &&
                    !connectionString.Contains("SSL Mode=VerifyFull", StringComparison.OrdinalIgnoreCase))
                {
                    failures.Add("ConnectionStrings:IdentityConnection must enforce TLS with SSL Mode=Require or SSL Mode=VerifyFull in production.");
                }
            }
        }

        return failures.Count > 0
            ? ValidateOptionsResult.Fail(failures)
            : ValidateOptionsResult.Success;
    }
}

internal sealed class SessionSecurityOptionsValidation : IValidateOptions<SessionSecurityOptions>
{
    public ValidateOptionsResult Validate(string? name, SessionSecurityOptions options)
    {
        var failures = new List<string>();

        if (options.MaxActiveSessions < 1)
        {
            failures.Add("SessionSecurity:MaxActiveSessions must be at least 1.");
        }

        if (options.IdleTimeoutMinutes < 5)
        {
            failures.Add("SessionSecurity:IdleTimeoutMinutes must be at least 5.");
        }

        if (options.AbsoluteLifetimeDays < 1)
        {
            failures.Add("SessionSecurity:AbsoluteLifetimeDays must be at least 1.");
        }

        return failures.Count > 0
            ? ValidateOptionsResult.Fail(failures)
            : ValidateOptionsResult.Success;
    }
}

internal sealed class DataRetentionOptionsValidation : IValidateOptions<DataRetentionOptions>
{
    public ValidateOptionsResult Validate(string? name, DataRetentionOptions options)
    {
        var failures = new List<string>();

        if (options.EnableCleanupService && options.CleanupIntervalMinutes < 5)
        {
            failures.Add("DataRetention:CleanupIntervalMinutes must be at least 5 when cleanup service is enabled.");
        }

        if (options.AuditRetentionDays < 1)
        {
            failures.Add("DataRetention:AuditRetentionDays must be at least 1.");
        }

        if (options.RevokedSessionRetentionDays < 1)
        {
            failures.Add("DataRetention:RevokedSessionRetentionDays must be at least 1.");
        }

        if (options.ExpiredVerificationTokenRetentionDays < 1)
        {
            failures.Add("DataRetention:ExpiredVerificationTokenRetentionDays must be at least 1.");
        }

        if (options.ExpiredInvitationRetentionDays < 1)
        {
            failures.Add("DataRetention:ExpiredInvitationRetentionDays must be at least 1.");
        }

        if (options.PublishedOutboxRetentionDays < 1)
        {
            failures.Add("DataRetention:PublishedOutboxRetentionDays must be at least 1.");
        }

        return failures.Count > 0
            ? ValidateOptionsResult.Fail(failures)
            : ValidateOptionsResult.Success;
    }
}

internal sealed class TrustedGatewayOptionsValidation(IHostEnvironment environment) : IValidateOptions<TrustedGatewayOptions>
{
    public ValidateOptionsResult Validate(string? name, TrustedGatewayOptions options)
    {
        var failures = new List<string>();

        if (string.IsNullOrWhiteSpace(options.SignatureHeaderName))
            failures.Add("Security:TrustedGateway:SignatureHeaderName is required.");

        if (string.IsNullOrWhiteSpace(options.TimestampHeaderName))
            failures.Add("Security:TrustedGateway:TimestampHeaderName is required.");

        if (string.IsNullOrWhiteSpace(options.KeyIdHeaderName))
            failures.Add("Security:TrustedGateway:KeyIdHeaderName is required.");

        if (string.IsNullOrWhiteSpace(options.SourceHeaderName))
            failures.Add("Security:TrustedGateway:SourceHeaderName is required.");

        if (string.IsNullOrWhiteSpace(options.NonceHeaderName))
            failures.Add("Security:TrustedGateway:NonceHeaderName is required.");

        if (string.IsNullOrWhiteSpace(options.ContentHashHeaderName))
            failures.Add("Security:TrustedGateway:ContentHashHeaderName is required.");

        if (options.RequireTrustedGateway)
        {
            if (options.Keys.Count == 0)
                failures.Add("Security:TrustedGateway:Keys must contain at least one signing key.");

            if (string.IsNullOrWhiteSpace(options.CurrentKeyId))
                failures.Add("Security:TrustedGateway:CurrentKeyId is required when trusted gateway enforcement is enabled.");

            if (options.AllowedClockSkewSeconds is < 5 or > 300)
                failures.Add("Security:TrustedGateway:AllowedClockSkewSeconds must be between 5 and 300.");

            if (options.ReplayProtectionWindowSeconds is < 30 or > 600)
                failures.Add("Security:TrustedGateway:ReplayProtectionWindowSeconds must be between 30 and 600.");

            if (options.AllowedSources.Length == 0)
                failures.Add("Security:TrustedGateway:AllowedSources must contain at least one source.");

            if (!options.Keys.Any(x => x.Enabled && string.Equals(x.KeyId, options.CurrentKeyId, StringComparison.Ordinal)))
                failures.Add("Security:TrustedGateway:CurrentKeyId must reference an enabled key.");

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

            if (environment.IsProduction() && options.AllowedGatewayProxies.Length == 0 && options.AllowedGatewayNetworks.Length == 0)
            {
                failures.Add("Security:TrustedGateway must define at least one allowed gateway proxy or network in production.");
            }
        }

        return failures.Count > 0
            ? ValidateOptionsResult.Fail(failures)
            : ValidateOptionsResult.Success;
    }
}

internal sealed class TokenValidationCacheOptionsValidation(IHostEnvironment environment) : IValidateOptions<TokenValidationCacheOptions>
{
    public ValidateOptionsResult Validate(string? name, TokenValidationCacheOptions options)
    {
        var failures = new List<string>();

        if (options.AbsoluteExpirationSeconds is < 0 or > 300)
        {
            failures.Add("Security:TokenValidationCache:AbsoluteExpirationSeconds must be between 0 and 300.");
        }

        if (options.NegativeAbsoluteExpirationSeconds is < 0 or > 120)
        {
            failures.Add("Security:TokenValidationCache:NegativeAbsoluteExpirationSeconds must be between 0 and 120.");
        }

        if (options.NegativeAbsoluteExpirationSeconds > options.AbsoluteExpirationSeconds && options.AbsoluteExpirationSeconds > 0)
        {
            failures.Add("Security:TokenValidationCache:NegativeAbsoluteExpirationSeconds must be less than or equal to AbsoluteExpirationSeconds.");
        }

        if (string.IsNullOrWhiteSpace(options.KeyPrefix))
        {
            failures.Add("Security:TokenValidationCache:KeyPrefix is required.");
        }

        if (environment.IsProduction() &&
            options.EnableCache &&
            options.AbsoluteExpirationSeconds > 15)
        {
            failures.Add("Security:TokenValidationCache:AbsoluteExpirationSeconds must be less than or equal to 15 in production.");
        }

        return failures.Count > 0
            ? ValidateOptionsResult.Fail(failures)
            : ValidateOptionsResult.Success;
    }
}

internal sealed class AuthDataProtectionOptionsValidation(IHostEnvironment environment) : IValidateOptions<AuthDataProtectionOptions>
{
    public ValidateOptionsResult Validate(string? name, AuthDataProtectionOptions options)
    {
        var failures = new List<string>();

        if (string.IsNullOrWhiteSpace(options.ApplicationName))
        {
            failures.Add("Infrastructure:DataProtection:ApplicationName is required.");
        }

        if (!string.IsNullOrWhiteSpace(options.KeyRingPath) && !Path.IsPathFullyQualified(options.KeyRingPath))
        {
            failures.Add("Infrastructure:DataProtection:KeyRingPath must be an absolute path when configured.");
        }

        if (environment.IsProduction() &&
            options.RequirePersistentKeyRingInProduction &&
            string.IsNullOrWhiteSpace(options.KeyRingPath))
        {
            failures.Add("Infrastructure:DataProtection:KeyRingPath is required in production when persistent keys are enforced.");
        }

        return failures.Count > 0
            ? ValidateOptionsResult.Fail(failures)
            : ValidateOptionsResult.Success;
    }
}

internal sealed class DistributedCacheOptionsValidation(IHostEnvironment environment) : IValidateOptions<DistributedCacheOptions>
{
    public ValidateOptionsResult Validate(string? name, DistributedCacheOptions options)
    {
        var failures = new List<string>();

        if (!string.Equals(options.Provider, "Redis", StringComparison.OrdinalIgnoreCase) &&
            !string.Equals(options.Provider, "Memory", StringComparison.OrdinalIgnoreCase))
        {
            failures.Add("Infrastructure:DistributedCache:Provider must be Redis or Memory.");
        }

        if (string.IsNullOrWhiteSpace(options.InstanceName))
        {
            failures.Add("Infrastructure:DistributedCache:InstanceName is required.");
        }

        if (options.ConnectTimeoutMilliseconds < 100)
        {
            failures.Add("Infrastructure:DistributedCache:ConnectTimeoutMilliseconds must be at least 100.");
        }

        if (options.AsyncTimeoutMilliseconds < 100)
        {
            failures.Add("Infrastructure:DistributedCache:AsyncTimeoutMilliseconds must be at least 100.");
        }

        if (options.SyncTimeoutMilliseconds < 100)
        {
            failures.Add("Infrastructure:DistributedCache:SyncTimeoutMilliseconds must be at least 100.");
        }

        if (options.ConnectRetry < 0 || options.ConnectRetry > 10)
        {
            failures.Add("Infrastructure:DistributedCache:ConnectRetry must be between 0 and 10.");
        }

        if (string.Equals(options.Provider, "Redis", StringComparison.OrdinalIgnoreCase) && string.IsNullOrWhiteSpace(options.RedisConnectionString))
        {
            failures.Add("Infrastructure:DistributedCache:RedisConnectionString is required when Provider is Redis.");
        }

        if (environment.IsProduction() &&
            string.Equals(options.Provider, "Memory", StringComparison.OrdinalIgnoreCase))
        {
            failures.Add("Infrastructure:DistributedCache:Provider cannot be Memory in production.");
        }

        return failures.Count > 0
            ? ValidateOptionsResult.Fail(failures)
            : ValidateOptionsResult.Success;
    }
}
