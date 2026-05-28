// <copyright file="StartupValidationTests.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using System.Text.Json;
using FluentAssertions;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.FileProviders;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Options;
using Norge360.Auth.API.Security;
using Norge360.Auth.Application.Options;

namespace Norge360.Auth.Api.FunctionalTests.Startup;

public sealed class StartupValidationTests
{
    [Fact]
    public void Startup_Should_Fail_In_Production_When_JwtSigningKey_Is_Missing()
    {
        var validation = ValidateJwtOptions(
            new JwtOptions
            {
                Issuer = "https://auth.Norge360.com",
                Audience = "api://norge360",
                AccessTokenMinutes = 15,
                RefreshTokenHours = 8,
                RefreshTokenPersistentDays = 14,
                SigningKeys = []
            },
            new TestHostEnvironment(Environments.Production));

        validation.Failed.Should().BeTrue();
        validation.Failures.Should().Contain(message => message.Contains("Jwt:SigningKeys", StringComparison.Ordinal));
    }

    [Fact]
    public void Startup_Should_Fail_In_Production_When_TokenTransport_Mode_Is_BodyOnly()
    {
        var validator = new TokenTransportOptionsValidation(new TestHostEnvironment(Environments.Production));
        var result = validator.Validate(
            null,
            new TokenTransportOptions
            {
                Mode = TokenTransportModes.BodyOnly,
                AccessCookieName = "__Secure-Norge360-access",
                RefreshCookieName = "__Secure-Norge360-refresh",
                SessionCookieName = "__Secure-Norge360-session",
                AccessCookiePath = "/",
                RefreshCookiePath = "/api/auth",
                SessionCookiePath = "/api/auth",
                SameSite = "Lax"
            });

        result.Failed.Should().BeTrue();
        result.Failures.Should().Contain(message => message.Contains("Security:TokenTransport:Mode must be CookiesOnly outside development.", StringComparison.Ordinal));
    }

    [Fact]
    public void Startup_Should_Fail_In_Production_When_CookieNames_Do_Not_Use_Secure_Prefix()
    {
        var validator = new TokenTransportOptionsValidation(new TestHostEnvironment(Environments.Production));
        var result = validator.Validate(
            null,
            new TokenTransportOptions
            {
                Mode = TokenTransportModes.CookiesOnly,
                AccessCookieName = "Norge360-access",
                RefreshCookieName = "Norge360-refresh",
                SessionCookieName = "Norge360-session",
                AccessCookiePath = "/",
                RefreshCookiePath = "/api/auth",
                SessionCookiePath = "/api/auth",
                SameSite = "Lax"
            });

        result.Failed.Should().BeTrue();
        result.Failures.Should().Contain(message => message.Contains("AccessCookieName must start with __Secure- or __Host-", StringComparison.Ordinal));
        result.Failures.Should().Contain(message => message.Contains("RefreshCookieName must start with __Secure- or __Host-", StringComparison.Ordinal));
        result.Failures.Should().Contain(message => message.Contains("SessionCookieName must start with __Secure- or __Host-", StringComparison.Ordinal));
    }

    [Fact]
    public void Startup_Should_Fail_In_Production_When_HostPrefixed_Cookies_Use_CookieDomain()
    {
        var validator = new TokenTransportOptionsValidation(new TestHostEnvironment(Environments.Production));
        var result = validator.Validate(
            null,
            new TokenTransportOptions
            {
                Mode = TokenTransportModes.CookiesOnly,
                AccessCookieName = "__Host-Norge360-access",
                RefreshCookieName = "__Host-Norge360-refresh",
                SessionCookieName = "__Host-Norge360-session",
                AccessCookiePath = "/",
                RefreshCookiePath = "/",
                SessionCookiePath = "/",
                CookieDomain = ".Norge360.com",
                SameSite = "Lax"
            });

        result.Failed.Should().BeTrue();
        result.Failures.Should().Contain(message => message.Contains("AccessCookieName cannot use __Host- when CookieDomain is configured.", StringComparison.Ordinal));
        result.Failures.Should().Contain(message => message.Contains("RefreshCookieName cannot use __Host- when CookieDomain is configured.", StringComparison.Ordinal));
        result.Failures.Should().Contain(message => message.Contains("SessionCookieName cannot use __Host- when CookieDomain is configured.", StringComparison.Ordinal));
    }

    [Fact]
    public void Startup_Should_Fail_In_Production_When_Cors_Uses_Wildcard_With_Credentials()
    {
        var validator = new ApiCorsOptionsValidation(new TestHostEnvironment(Environments.Production));
        var result = validator.Validate(
            null,
            new ApiCorsOptions
            {
                AllowedOrigins = ["*"],
                AllowCredentials = true
            });

        result.Failed.Should().BeTrue();
        result.Failures.Should().Contain(message => message.Contains("AllowedOrigins cannot contain '*'", StringComparison.Ordinal));
    }

    [Fact]
    public void Startup_Should_Accept_Production_Norge360_Cors_Origins()
    {
        var validator = new ApiCorsOptionsValidation(new TestHostEnvironment(Environments.Production));
        var result = validator.Validate(
            null,
            new ApiCorsOptions
            {
                AllowedOrigins =
                [
                    "https://Norge360.com",
                    "https://www.Norge360.com"
                ],
                AllowCredentials = true
            });

        result.Failed.Should().BeFalse();
    }

    [Fact]
    public void Startup_Should_Reject_Localhost_Cors_Origin_In_Production()
    {
        var validator = new ApiCorsOptionsValidation(new TestHostEnvironment(Environments.Production));
        var result = validator.Validate(
            null,
            new ApiCorsOptions
            {
                AllowedOrigins = ["http://localhost:7002"],
                AllowCredentials = true
            });

        result.Failed.Should().BeTrue();
        result.Failures.Should().Contain(message => message.Contains("loopback origin", StringComparison.Ordinal));
    }

    [Fact]
    public void Local_Config_Should_Allow_Auth_And_Account_Web_Cookie_Origins()
    {
        using var document = JsonDocument.Parse(File.ReadAllText(FindRepoFile("services/auth/src/Norge360.Auth.API/appsettings.json")));
        var origins = document.RootElement
            .GetProperty("Security")
            .GetProperty("Cors")
            .GetProperty("AllowedOrigins")
            .EnumerateArray()
            .Select(item => item.GetString())
            .ToArray();

        origins.Should().Contain("http://localhost:7002");
        origins.Should().Contain("http://localhost:7004");
    }

    [Fact]
    public void Production_Config_Should_Mark_Anonymous_Auth_Flows_Tenant_Optional()
    {
        using var document = JsonDocument.Parse(File.ReadAllText(FindRepoFile("services/auth/src/Norge360.Auth.API/appsettings.Production.json")));
        var prefixes = document.RootElement
            .GetProperty("Security")
            .GetProperty("TenantResolution")
            .GetProperty("TenantOptionalPathPrefixes")
            .EnumerateArray()
            .Select(item => item.GetString())
            .ToArray();

        prefixes.Should().Contain("/api/auth/register");
        prefixes.Should().Contain("/api/auth/login");
        prefixes.Should().Contain("/api/auth/forgot-password");
    }

    [Fact]
    public void Production_Config_Should_Keep_TokenValidationCache_Stale_Window_Short()
    {
        using var document = JsonDocument.Parse(File.ReadAllText(FindRepoFile("services/auth/src/Norge360.Auth.API/appsettings.Production.json")));
        var tokenCache = document.RootElement
            .GetProperty("Security")
            .GetProperty("TokenValidationCache");

        var validTtlSeconds = tokenCache.GetProperty("AbsoluteExpirationSeconds").GetInt32();
        var negativeTtlSeconds = tokenCache.GetProperty("NegativeAbsoluteExpirationSeconds").GetInt32();

        validTtlSeconds.Should().BeLessThanOrEqualTo(15);
        negativeTtlSeconds.Should().BeLessThanOrEqualTo(validTtlSeconds);
    }

    [Fact]
    public void Startup_Should_Fail_In_Production_When_TokenValidationCache_ValidTtl_Exceeds_15_Seconds()
    {
        var validation = ValidateTokenValidationCacheOptions(
            new TokenValidationCacheOptions
            {
                EnableCache = true,
                AbsoluteExpirationSeconds = 30,
                NegativeAbsoluteExpirationSeconds = 10,
                KeyPrefix = "auth:token-state"
            },
            new TestHostEnvironment(Environments.Production));

        validation.Failed.Should().BeTrue();
        validation.Failures.Should().Contain(message => message.Contains("AbsoluteExpirationSeconds must be less than or equal to 15 in production.", StringComparison.Ordinal));
    }

    [Fact]
    public void Startup_Should_Fail_When_AccountLifecycle_Cooldowns_Are_Out_Of_Range()
    {
        var validation = ValidateAccountLifecycleOptions(
            new AccountLifecycleOptions
            {
                RequireConfirmedEmailForLogin = true,
                EmailConfirmationTokenMinutes = 1440,
                PasswordResetTokenMinutes = 30,
                PasswordResetCooldownSeconds = 5,
                EmailChangeTokenMinutes = 30,
                EmailConfirmationResendCooldownSeconds = 7201,
                InvitationTokenMinutes = 10080,
                TokenBytes = 32,
                PublicAppBaseUrl = "https://auth.Norge360.com",
                ConfirmEmailPath = "/confirm-email",
                ResetPasswordPath = "/reset-password",
                ConfirmEmailChangePath = "/confirm-email-change"
            },
            new TestHostEnvironment(Environments.Production));

        validation.Failed.Should().BeTrue();
        validation.Failures.Should().Contain(message => message.Contains("PasswordResetCooldownSeconds", StringComparison.Ordinal));
        validation.Failures.Should().Contain(message => message.Contains("EmailConfirmationResendCooldownSeconds", StringComparison.Ordinal));
    }

    [Fact]
    public void Startup_Should_Fail_In_Production_When_IdentityConnection_Is_Loopback()
    {
        var config = new ConfigurationBuilder()
            .AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["ConnectionStrings:IdentityConnection"] = "Host=localhost;Port=5432;Database=AuthDb;Username=postgres;Password=test-only-placeholder;SSL Mode=Require;Trust Server Certificate=true"
            })
            .Build();

        var validation = ValidateDatabaseOptions(
            new DatabaseOptions { ApplyMigrationsOnStartup = false },
            new TestHostEnvironment(Environments.Production),
            config);

        validation.Failed.Should().BeTrue();
        validation.Failures.Should().Contain(message => message.Contains("ConnectionStrings:IdentityConnection cannot point to localhost in production.", StringComparison.Ordinal));
    }

    [Fact]
    public void Production_Should_Fail_When_TokenValidationCache_Uses_MemoryProvider()
    {
        var options = new DistributedCacheOptions
        {
            Provider = "Memory",
            RequireExternalProviderInProduction = false,
            InstanceName = "Norge360:Auth:",
            ConnectTimeoutMilliseconds = 5000,
            AsyncTimeoutMilliseconds = 5000,
            SyncTimeoutMilliseconds = 5000,
            ConnectRetry = 3
        };

        var validation = ValidateDistributedCacheOptions(options, new TestHostEnvironment(Environments.Production));

        validation.Failed.Should().BeTrue();
        validation.Failures.Should().Contain(message => message.Contains("Provider cannot be Memory in production.", StringComparison.Ordinal));
    }

    [Fact]
    public void Development_Smtp_InvitationDeliveryOptions_Should_Bind_From_Configuration()
    {
        var config = new ConfigurationBuilder()
            .AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["InvitationDelivery:AcceptBaseUrl"] = "https://localhost:7146",
                ["InvitationDelivery:AcceptPath"] = "/invite/accept",
                ["InvitationDelivery:SenderName"] = "Norge360App",
                ["InvitationDelivery:SenderAddress"] = "sender@example.com",
                ["InvitationDelivery:DisableDelivery"] = "false",
                ["InvitationDelivery:Provider"] = "smtp",
                ["InvitationDelivery:SmtpHost"] = "smtp.gmail.com",
                ["InvitationDelivery:SmtpPort"] = "587",
                ["InvitationDelivery:SmtpUseStartTls"] = "true",
                ["InvitationDelivery:SmtpUserName"] = "sender@example.com",
                ["InvitationDelivery:SmtpPassword"] = "test-only-app-password-placeholder",
                ["InvitationDelivery:ResendThrottleSeconds"] = "60",
                ["InvitationDelivery:MaxResends"] = "5"
            })
            .Build();
        var options = config.GetSection(InvitationDeliveryOptions.SectionName).Get<InvitationDeliveryOptions>()!;

        options.Provider.Should().Be("smtp");
        options.SmtpHost.Should().Be("smtp.gmail.com");
        options.SmtpPort.Should().Be(587);
        options.SmtpUseStartTls.Should().BeTrue();
        options.SmtpUserName.Should().Be("sender@example.com");
        options.SmtpPassword.Should().Be("test-only-app-password-placeholder");

        var validation = ValidateInvitationDeliveryOptions(options, new TestHostEnvironment(Environments.Development));
        validation.Failed.Should().BeFalse();
    }

    [Fact]
    public void Startup_Should_Fail_When_Smtp_InvitationDelivery_Is_Enabled_And_Required_Fields_Are_Missing()
    {
        var validation = ValidateInvitationDeliveryOptions(
            new InvitationDeliveryOptions
            {
                AcceptBaseUrl = "https://localhost:7146",
                AcceptPath = "/invite/accept",
                SenderName = "Norge360App",
                SenderAddress = "sender@example.com",
                DisableDelivery = false,
                Provider = "smtp",
                SmtpHost = "",
                SmtpPort = 587,
                SmtpUseStartTls = true,
                SmtpUserName = "sender@example.com",
                SmtpPassword = "",
                ResendThrottleSeconds = 60,
                MaxResends = 5
            },
            new TestHostEnvironment(Environments.Development));

        validation.Failed.Should().BeTrue();
        validation.Failures.Should().Contain(message => message.Contains("InvitationDelivery:SmtpHost is required when SMTP delivery is enabled.", StringComparison.Ordinal));
        validation.Failures.Should().Contain(message => message.Contains("InvitationDelivery:SmtpPassword is required when SmtpUserName is configured.", StringComparison.Ordinal));
    }

    [Fact]
    public void Startup_Should_Not_Require_Smtp_Fields_When_InvitationDelivery_Uses_Notification_Pipeline()
    {
        var validation = ValidateInvitationDeliveryOptions(
            new InvitationDeliveryOptions
            {
                AcceptBaseUrl = "https://localhost:7146",
                AcceptPath = "/invite/accept",
                SenderName = "Norge360App",
                SenderAddress = "sender@example.com",
                DisableDelivery = false,
                Provider = "notification",
                SmtpHost = "",
                SmtpPort = 587,
                SmtpUseStartTls = true,
                ResendThrottleSeconds = 60,
                MaxResends = 5
            },
            new TestHostEnvironment(Environments.Development));

        validation.Failed.Should().BeFalse();
    }

    private static ValidateOptionsResult ValidateJwtOptions(JwtOptions options, IHostEnvironment environment)
    {
        var validatorType = Type.GetType(
                "Norge360.Auth.Infrastructure.DependencyInjection.JwtOptionsValidation, Norge360.Auth.Infrastructure",
                throwOnError: true)!
            ;
        var validator = Activator.CreateInstance(validatorType, environment)!;
        return (ValidateOptionsResult)validatorType.GetMethod("Validate")!.Invoke(validator, [null, options])!;
    }

    private static ValidateOptionsResult ValidateDatabaseOptions(DatabaseOptions options, IHostEnvironment environment, IConfiguration configuration)
    {
        var validatorType = Type.GetType(
                "Norge360.Auth.Infrastructure.DependencyInjection.DatabaseOptionsValidation, Norge360.Auth.Infrastructure",
                throwOnError: true)!
            ;
        var validator = Activator.CreateInstance(validatorType, environment, configuration)!;
        return (ValidateOptionsResult)validatorType.GetMethod("Validate")!.Invoke(validator, [null, options])!;
    }

    private static ValidateOptionsResult ValidateInvitationDeliveryOptions(InvitationDeliveryOptions options, IHostEnvironment environment)
    {
        var validatorType = Type.GetType(
                "Norge360.Auth.Infrastructure.DependencyInjection.InvitationDeliveryOptionsValidation, Norge360.Auth.Infrastructure",
                throwOnError: true)!
            ;
        var validator = Activator.CreateInstance(validatorType, environment)!;
        return (ValidateOptionsResult)validatorType.GetMethod("Validate")!.Invoke(validator, [null, options])!;
    }

    private static ValidateOptionsResult ValidateDistributedCacheOptions(DistributedCacheOptions options, IHostEnvironment environment)
    {
        var validatorType = Type.GetType(
                "Norge360.Auth.Infrastructure.DependencyInjection.DistributedCacheOptionsValidation, Norge360.Auth.Infrastructure",
                throwOnError: true)!
            ;
        var validator = Activator.CreateInstance(validatorType, environment)!;
        return (ValidateOptionsResult)validatorType.GetMethod("Validate")!.Invoke(validator, [null, options])!;
    }

    private static ValidateOptionsResult ValidateTokenValidationCacheOptions(TokenValidationCacheOptions options, IHostEnvironment environment)
    {
        var validatorType = Type.GetType(
                "Norge360.Auth.Infrastructure.DependencyInjection.TokenValidationCacheOptionsValidation, Norge360.Auth.Infrastructure",
                throwOnError: true)!
            ;
        var validator = Activator.CreateInstance(validatorType, environment)!;
        return (ValidateOptionsResult)validatorType.GetMethod("Validate")!.Invoke(validator, [null, options])!;
    }

    private static ValidateOptionsResult ValidateAccountLifecycleOptions(AccountLifecycleOptions options, IHostEnvironment environment)
    {
        var validatorType = Type.GetType(
                "Norge360.Auth.Infrastructure.DependencyInjection.AccountLifecycleOptionsValidation, Norge360.Auth.Infrastructure",
                throwOnError: true)!
            ;
        var validator = Activator.CreateInstance(validatorType, environment)!;
        return (ValidateOptionsResult)validatorType.GetMethod("Validate")!.Invoke(validator, [null, options])!;
    }

    private static string FindRepoFile(string relativePath)
    {
        var directory = new DirectoryInfo(AppContext.BaseDirectory);
        while (directory is not null)
        {
            var candidate = Path.Combine(directory.FullName, relativePath);
            if (File.Exists(candidate))
            {
                return candidate;
            }

            directory = directory.Parent;
        }

        throw new FileNotFoundException($"Could not find repository file '{relativePath}'.");
    }

    private sealed class TestHostEnvironment(string environmentName) : IHostEnvironment
    {
        public string EnvironmentName { get; set; } = environmentName;
        public string ApplicationName { get; set; } = "Norge360.Auth.Api.FunctionalTests";
        public string ContentRootPath { get; set; } = AppContext.BaseDirectory;
        public IFileProvider ContentRootFileProvider { get; set; } = new NullFileProvider();
    }
}
