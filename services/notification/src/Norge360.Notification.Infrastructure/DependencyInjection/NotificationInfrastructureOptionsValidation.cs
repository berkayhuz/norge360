// <copyright file="NotificationInfrastructureOptionsValidation.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Options;
using Npgsql;
using Norge360.Notification.Infrastructure.Integration;
using Norge360.Notification.Infrastructure.Modules.Email.Infrastructure.Options;
using Norge360.Notification.Infrastructure.Options;

namespace Norge360.Notification.Infrastructure.DependencyInjection;

public sealed class NotificationDatabaseOptionsValidation(
    IHostEnvironment environment,
    IConfiguration configuration) : IValidateOptions<NotificationDatabaseOptions>
{
    public ValidateOptionsResult Validate(string? name, NotificationDatabaseOptions options)
    {
        if (!environment.IsProduction())
        {
            return ValidateOptionsResult.Success;
        }

        var failures = new List<string>();
        if (options.ApplyMigrationsOnStartup)
        {
            failures.Add("Notification:Database:ApplyMigrationsOnStartup must be false in production.");
        }

        var connectionString = configuration.GetConnectionString("NotificationConnection");
        if (string.IsNullOrWhiteSpace(connectionString))
        {
            failures.Add("ConnectionStrings:NotificationConnection is required in production.");
        }
        else
        {
            ValidatePostgresConnectionString(connectionString, failures);
        }

        return failures.Count == 0 ? ValidateOptionsResult.Success : ValidateOptionsResult.Fail(failures);
    }

    private static void ValidatePostgresConnectionString(string connectionString, ICollection<string> failures)
    {
        NpgsqlConnectionStringBuilder builder;
        try
        {
            builder = new NpgsqlConnectionStringBuilder(connectionString);
        }
        catch (ArgumentException exception)
        {
            failures.Add($"ConnectionStrings:NotificationConnection is invalid: {exception.Message}");
            return;
        }

        if (IsUnsafeHost(builder.Host))
        {
            failures.Add("ConnectionStrings:NotificationConnection must not use localhost, loopback, or marker hosts in production.");
        }

        if (builder.SslMode is not (SslMode.Require or SslMode.VerifyFull))
        {
            failures.Add("ConnectionStrings:NotificationConnection must enforce TLS with SSL Mode=Require or SSL Mode=VerifyFull in production.");
        }

        if (string.Equals(builder.Username, "postgres", StringComparison.OrdinalIgnoreCase))
        {
            failures.Add("ConnectionStrings:NotificationConnection must not use the default postgres superuser in production.");
        }

        if (!string.IsNullOrWhiteSpace(builder.Password) &&
            (builder.Password.Length < 16 || ContainsUnsafeMarker(builder.Password)))
        {
            failures.Add("ConnectionStrings:NotificationConnection must use a strong production database password.");
        }
    }

    private static bool IsUnsafeHost(string host) =>
        string.IsNullOrWhiteSpace(host) ||
        Uri.CheckHostName(host) == UriHostNameType.Unknown ||
        ContainsUnsafeMarker(host);

    private static bool ContainsUnsafeMarker(string value)
    {
        var markers = new[] { "localhost", "127.0.0.1", "::1", "change_me", "replace", "local", "dev", "test" };
        return markers.Any(marker => value.Contains(marker, StringComparison.OrdinalIgnoreCase));
    }
}

public sealed class NotificationRabbitMqOptionsValidation(IHostEnvironment environment) : IValidateOptions<NotificationRabbitMqOptions>
{
    public ValidateOptionsResult Validate(string? name, NotificationRabbitMqOptions options)
    {
        if (!environment.IsProduction())
        {
            return ValidateOptionsResult.Success;
        }

        var failures = new List<string>();
        if (IsUnsafeHost(options.Host))
        {
            failures.Add("Notification:RabbitMq:Host must be a production broker host.");
        }

        if (!options.UseTls)
        {
            failures.Add("Notification:RabbitMq:UseTls must be true in production.");
        }

        if (options.Port == 5672)
        {
            failures.Add("Notification:RabbitMq:Port must not use the non-TLS AMQP port in production.");
        }

        if (string.Equals(options.Username, "guest", StringComparison.OrdinalIgnoreCase) ||
            ContainsUnsafeMarker(options.Username))
        {
            failures.Add("Notification:RabbitMq:Username must not be guest or contain local/dev/test markers in production.");
        }

        if (string.IsNullOrWhiteSpace(options.Password) ||
            options.Password.Length < 16 ||
            string.Equals(options.Password, "guest", StringComparison.OrdinalIgnoreCase) ||
            ContainsUnsafeMarker(options.Password))
        {
            failures.Add("Notification:RabbitMq:Password must be a strong production secret.");
        }

        if (!options.UseQuorumQueue)
        {
            failures.Add("Notification:RabbitMq:UseQuorumQueue must be true in production.");
        }

        ValidateName(options.QueueName, "Notification:RabbitMq:QueueName", failures);
        ValidateName(options.DeadLetterExchangeName, "Notification:RabbitMq:DeadLetterExchangeName", failures);
        ValidateName(options.DeadLetterQueueName, "Notification:RabbitMq:DeadLetterQueueName", failures);
        ValidateName(options.DeadLetterRoutingKey, "Notification:RabbitMq:DeadLetterRoutingKey", failures);

        return failures.Count == 0 ? ValidateOptionsResult.Success : ValidateOptionsResult.Fail(failures);
    }

    private static void ValidateName(string value, string settingName, ICollection<string> failures)
    {
        if (string.IsNullOrWhiteSpace(value) || ContainsUnsafeMarker(value))
        {
            failures.Add($"{settingName} must be configured without local/dev/test markers in production.");
        }
    }

    private static bool IsUnsafeHost(string host)
    {
        if (string.IsNullOrWhiteSpace(host) || ContainsUnsafeMarker(host))
        {
            return true;
        }

        return Uri.CheckHostName(host) == UriHostNameType.Unknown;
    }

    private static bool ContainsUnsafeMarker(string value)
    {
        var markers = new[] { "localhost", "127.0.0.1", "::1", "change_me", "replace", "local", "dev", "test" };
        return markers.Any(marker => value.Contains(marker, StringComparison.OrdinalIgnoreCase));
    }
}

public sealed class NotificationIntegrationConsumerOptionsValidation(IHostEnvironment environment)
    : IValidateOptions<NotificationIntegrationConsumerOptions>
{
    public ValidateOptionsResult Validate(string? name, NotificationIntegrationConsumerOptions options)
    {
        if (!environment.IsProduction())
        {
            return ValidateOptionsResult.Success;
        }

        var failures = new List<string>();
        if (!options.Enabled)
        {
            failures.Add("Notification:IntegrationConsumer:Enabled must be true in production so account and security notifications are consumed.");
        }

        if (string.IsNullOrWhiteSpace(options.QueueName) || ContainsUnsafeMarker(options.QueueName))
        {
            failures.Add("Notification:IntegrationConsumer:QueueName must be configured without local/dev/test markers in production.");
        }

        return failures.Count == 0 ? ValidateOptionsResult.Success : ValidateOptionsResult.Fail(failures);
    }

    private static bool ContainsUnsafeMarker(string value)
    {
        var markers = new[] { "localhost", "127.0.0.1", "::1", "change_me", "replace", "local", "dev", "test" };
        return markers.Any(marker => value.Contains(marker, StringComparison.OrdinalIgnoreCase));
    }
}

public sealed class NotificationEmailProviderOptionsValidation(
    IHostEnvironment environment) : IValidateOptions<EmailProviderOptions>
{
    public ValidateOptionsResult Validate(string? name, EmailProviderOptions options)
    {
        var provider = options.Provider.Trim().ToLowerInvariant();
        if (provider is not ("smtp" or "ses" or "amazon-ses" or "amazonses" or "console" or "disabled"))
        {
            return ValidateOptionsResult.Fail("Notification:Email:Provider must be smtp, ses, console, or disabled.");
        }

        if (environment.IsProduction() && provider is "console" or "disabled")
        {
            return ValidateOptionsResult.Fail("Notification:Email:Provider cannot be console or disabled in production.");
        }

        return ValidateOptionsResult.Success;
    }
}

public sealed class SmtpEmailProviderOptionsValidation(
    IHostEnvironment environment,
    IOptions<EmailProviderOptions> providerOptions) : IValidateOptions<SmtpEmailProviderOptions>
{
    public ValidateOptionsResult Validate(string? name, SmtpEmailProviderOptions options)
    {
        if (!UsesSmtp(providerOptions.Value.Provider))
        {
            return ValidateOptionsResult.Success;
        }

        var failures = new List<string>();
        if (string.IsNullOrWhiteSpace(options.Host) || options.Port is < 1 or > 65535)
        {
            failures.Add("Notification:Email:Smtp host and port are required when SMTP is selected.");
        }

        if (string.IsNullOrWhiteSpace(options.FromAddress) || !IsEmailLike(options.FromAddress))
        {
            failures.Add("Notification:Email:Smtp:FromAddress must be a valid sender address.");
        }

        if (string.IsNullOrWhiteSpace(options.FromName))
        {
            failures.Add("Notification:Email:Smtp:FromName is required.");
        }

        if (!string.IsNullOrWhiteSpace(options.UserName) && string.IsNullOrWhiteSpace(options.Password))
        {
            failures.Add("Notification:Email:Smtp:Password is required when UserName is configured.");
        }

        var approvedDomains = providerOptions.Value.ApprovedSenderDomains;
        if (!NotificationSenderDomainValidation.IsApprovedSenderDomain(options.FromAddress, approvedDomains))
        {
            failures.Add("Notification:Email:Smtp:FromAddress must use an approved sender domain.");
        }

        if (environment.IsProduction())
        {
            if (IsUnsafeHost(options.Host))
            {
                failures.Add("Notification:Email:Smtp:Host must be a production SMTP host.");
            }

            if (!options.UseStartTls)
            {
                failures.Add("Notification:Email:Smtp:UseStartTls must be true in production.");
            }

            if (string.IsNullOrWhiteSpace(options.UserName) || string.IsNullOrWhiteSpace(options.Password))
            {
                failures.Add("Notification:Email:Smtp requires credentials in production.");
            }

            if (ContainsUnsafeMarker(options.FromAddress) ||
                ContainsUnsafeMarker(options.FromName) ||
                ContainsUnsafeMarker(options.UserName ?? string.Empty) ||
                ContainsUnsafeMarker(options.Password ?? string.Empty))
            {
                failures.Add("Notification:Email:Smtp settings must not contain local/dev/test markers in production.");
            }
        }

        return failures.Count == 0 ? ValidateOptionsResult.Success : ValidateOptionsResult.Fail(failures);
    }

    private static bool UsesSmtp(string provider) =>
        provider.Trim().Equals("smtp", StringComparison.OrdinalIgnoreCase);

    private static bool IsEmailLike(string value) =>
        value.Contains('@', StringComparison.Ordinal) &&
        value.Contains('.', StringComparison.Ordinal);

    private static bool IsUnsafeHost(string value) =>
        string.IsNullOrWhiteSpace(value) ||
        Uri.CheckHostName(value) == UriHostNameType.Unknown ||
        ContainsUnsafeMarker(value);

    private static bool ContainsUnsafeMarker(string value)
    {
        var markers = new[] { "localhost", "127.0.0.1", "::1", "change_me", "replace", "local", "dev", "test" };
        return markers.Any(marker => value.Contains(marker, StringComparison.OrdinalIgnoreCase));
    }
}

public sealed class AmazonSesEmailProviderOptionsValidation(
    IHostEnvironment environment,
    IOptions<EmailProviderOptions> providerOptions) : IValidateOptions<AmazonSesEmailProviderOptions>
{
    public ValidateOptionsResult Validate(string? name, AmazonSesEmailProviderOptions options)
    {
        if (!UsesSes(providerOptions.Value.Provider))
        {
            return ValidateOptionsResult.Success;
        }

        var failures = new List<string>();
        if (string.IsNullOrWhiteSpace(options.Region))
        {
            failures.Add("Notification:Email:AmazonSes:Region is required when SES is selected.");
        }

        if (string.IsNullOrWhiteSpace(options.FromAddress) || !IsEmailLike(options.FromAddress))
        {
            failures.Add("Notification:Email:AmazonSes:FromAddress must be a valid sender address.");
        }

        if (string.IsNullOrWhiteSpace(options.FromName))
        {
            failures.Add("Notification:Email:AmazonSes:FromName is required.");
        }

        var approvedDomains = providerOptions.Value.ApprovedSenderDomains;
        if (!NotificationSenderDomainValidation.IsApprovedSenderDomain(options.FromAddress, approvedDomains))
        {
            failures.Add("Notification:Email:AmazonSes:FromAddress must use an approved sender domain.");
        }

        if (environment.IsProduction())
        {
            if (ContainsUnsafeMarker(options.Region) ||
                ContainsUnsafeMarker(options.FromAddress) ||
                ContainsUnsafeMarker(options.FromName) ||
                ContainsUnsafeMarker(options.AccessKeyId ?? string.Empty) ||
                ContainsUnsafeMarker(options.SecretAccessKey ?? string.Empty))
            {
                failures.Add("Notification:Email:AmazonSes settings must not contain local/dev/test markers in production.");
            }

            if (!string.IsNullOrWhiteSpace(options.EndpointUrl) &&
                (!Uri.TryCreate(options.EndpointUrl, UriKind.Absolute, out var endpoint) ||
                 endpoint.Scheme != Uri.UriSchemeHttps ||
                 ContainsUnsafeMarker(endpoint.Host)))
            {
                failures.Add("Notification:Email:AmazonSes:EndpointUrl must be an HTTPS production endpoint when configured.");
            }
        }

        return failures.Count == 0 ? ValidateOptionsResult.Success : ValidateOptionsResult.Fail(failures);
    }

    private static bool UsesSes(string provider)
    {
        var normalized = provider.Trim().ToLowerInvariant();
        return normalized is "ses" or "amazon-ses" or "amazonses";
    }

    private static bool IsEmailLike(string value) =>
        value.Contains('@', StringComparison.Ordinal) &&
        value.Contains('.', StringComparison.Ordinal);

    private static bool ContainsUnsafeMarker(string value)
    {
        var markers = new[] { "localhost", "127.0.0.1", "::1", "change_me", "replace", "local", "dev", "test" };
        return markers.Any(marker => value.Contains(marker, StringComparison.OrdinalIgnoreCase));
    }
}

internal static class NotificationSenderDomainValidation
{
    public static bool IsApprovedSenderDomain(string fromAddress, IEnumerable<string> approvedDomains)
    {
        if (string.IsNullOrWhiteSpace(fromAddress))
        {
            return false;
        }

        var atIndex = fromAddress.IndexOf('@');
        if (atIndex < 0 || atIndex == fromAddress.Length - 1)
        {
            return false;
        }

        var domain = fromAddress[(atIndex + 1)..];
        return approvedDomains.Any(approved =>
            !string.IsNullOrWhiteSpace(approved) &&
            string.Equals(domain, approved.Trim(), StringComparison.OrdinalIgnoreCase));
    }
}
