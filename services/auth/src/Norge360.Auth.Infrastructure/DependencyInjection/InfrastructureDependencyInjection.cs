// <copyright file="InfrastructureDependencyInjection.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.DataProtection;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Caching.Distributed;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using Microsoft.IdentityModel.Tokens;
using Norge360.AspNetCore.TrustedGateway.Abstractions;
using Norge360.AspNetCore.TrustedGateway.Options;
using Norge360.AspNetCore.TrustedGateway.ReplayProtection;
using Norge360.AspNetCore.TrustedGateway.Signing;
using Norge360.AspNetCore.TrustedGateway.Validation;
using Norge360.Auth.Application.Abstractions;
using Norge360.Auth.Application.Options;
using Norge360.Auth.Domain.Entities;
using Norge360.Auth.Infrastructure.Persistence;
using Norge360.Auth.Infrastructure.Services;
using Norge360.Clock;
using Norge360.Messaging.RabbitMq.DependencyInjection;
using StackExchange.Redis;

namespace Norge360.Auth.Infrastructure.DependencyInjection;

public static class InfrastructureDependencyInjection
{
    public static IServiceCollection AddAuthInfrastructure(this IServiceCollection services, IConfiguration configuration)
    {
        services
            .AddOptions<JwtOptions>()
            .Bind(configuration.GetSection(JwtOptions.SectionName))
            .ValidateOnStart();

        services
            .AddOptions<IdentitySecurityOptions>()
            .Bind(configuration.GetSection(IdentitySecurityOptions.SectionName))
            .ValidateOnStart();

        services
            .AddOptions<AccountLifecycleOptions>()
            .Bind(configuration.GetSection(AccountLifecycleOptions.SectionName))
            .ValidateOnStart();

        services
            .AddOptions<InvitationDeliveryOptions>()
            .Bind(configuration.GetSection(InvitationDeliveryOptions.SectionName))
            .ValidateOnStart();

        services
            .AddOptions<PasswordPolicyOptions>()
            .Bind(configuration.GetSection(PasswordPolicyOptions.SectionName))
            .ValidateOnStart();

        services
            .AddOptions<SeedOptions>()
            .Bind(configuration.GetSection(SeedOptions.SectionName))
            .ValidateOnStart();

        services
            .AddOptions<DatabaseOptions>()
            .Bind(configuration.GetSection(DatabaseOptions.SectionName))
            .ValidateOnStart();

        services
            .AddOptions<AuthorizationOptions>()
            .Bind(configuration.GetSection(AuthorizationOptions.SectionName))
            .ValidateOnStart();

        services
            .AddOptions<SessionSecurityOptions>()
            .Bind(configuration.GetSection(SessionSecurityOptions.SectionName))
            .ValidateOnStart();

        services
            .AddOptions<DataRetentionOptions>()
            .Bind(configuration.GetSection(DataRetentionOptions.SectionName))
            .ValidateOnStart();

        services
            .AddOptions<OutboxOptions>()
            .Bind(configuration.GetSection(OutboxOptions.SectionName))
            .ValidateOnStart();

        services
            .AddOptions<SecurityAlertOptions>()
            .Bind(configuration.GetSection(SecurityAlertOptions.SectionName))
            .ValidateOnStart();

        services
            .AddOptions<TokenValidationCacheOptions>()
            .Bind(configuration.GetSection(TokenValidationCacheOptions.SectionName))
            .ValidateOnStart();

        services
            .AddOptions<DistributedCacheOptions>()
            .Bind(configuration.GetSection(DistributedCacheOptions.SectionName))
            .ValidateOnStart();

        services
            .AddOptions<AuthDataProtectionOptions>()
            .Bind(configuration.GetSection(AuthDataProtectionOptions.SectionName))
            .ValidateOnStart();

        services.AddSingleton<IValidateOptions<JwtOptions>, JwtOptionsValidation>();
        services.AddSingleton<IValidateOptions<IdentitySecurityOptions>, IdentitySecurityOptionsValidation>();
        services.AddSingleton<IValidateOptions<AccountLifecycleOptions>, AccountLifecycleOptionsValidation>();
        services.AddSingleton<IValidateOptions<InvitationDeliveryOptions>, InvitationDeliveryOptionsValidation>();
        services.AddSingleton<IValidateOptions<PasswordPolicyOptions>, PasswordPolicyOptionsValidation>();
        services.AddSingleton<IValidateOptions<AuthorizationOptions>, AuthorizationOptionsValidation>();
        services.AddSingleton<IValidateOptions<DatabaseOptions>, DatabaseOptionsValidation>();
        services.AddSingleton<IValidateOptions<SessionSecurityOptions>, SessionSecurityOptionsValidation>();
        services.AddSingleton<IValidateOptions<DataRetentionOptions>, DataRetentionOptionsValidation>();
        services.AddSingleton<IValidateOptions<TrustedGatewayOptions>, TrustedGatewayOptionsValidation>();
        services.AddSingleton<IValidateOptions<TokenValidationCacheOptions>, TokenValidationCacheOptionsValidation>();
        services.AddSingleton<IValidateOptions<DistributedCacheOptions>, DistributedCacheOptionsValidation>();
        services.AddSingleton<IValidateOptions<AuthDataProtectionOptions>, AuthDataProtectionOptionsValidation>();

        var connectionString = configuration.GetConnectionString("IdentityConnection")
            ?? throw new InvalidOperationException("Connection string 'IdentityConnection' is missing.");

        services.AddDbContext<AuthDbContext>(options =>
        {
            options.UseNpgsql(connectionString, npgsqlOptions =>
            {
                npgsqlOptions.EnableRetryOnFailure(5, TimeSpan.FromSeconds(10), null);
            });
        });

        var authDataProtectionOptions = configuration
            .GetSection(AuthDataProtectionOptions.SectionName)
            .Get<AuthDataProtectionOptions>()
            ?? new AuthDataProtectionOptions();

        var dataProtectionBuilder = services
            .AddDataProtection()
            .SetApplicationName(authDataProtectionOptions.ApplicationName);

        if (!string.IsNullOrWhiteSpace(authDataProtectionOptions.KeyRingPath))
        {
            dataProtectionBuilder.PersistKeysToFileSystem(new DirectoryInfo(authDataProtectionOptions.KeyRingPath));
        }

        var distributedCacheOptions = configuration
            .GetSection(DistributedCacheOptions.SectionName)
            .Get<DistributedCacheOptions>()
            ?? throw new InvalidOperationException("Infrastructure:DistributedCache configuration is missing.");

        services.AddSingleton(distributedCacheOptions);

        if (string.Equals(distributedCacheOptions.Provider, "Redis", StringComparison.OrdinalIgnoreCase))
        {
            if (string.IsNullOrWhiteSpace(distributedCacheOptions.RedisConnectionString))
            {
                throw new InvalidOperationException(
                    "Infrastructure:DistributedCache:RedisConnectionString is required when Provider is Redis.");
            }

            services.AddSingleton<IConnectionMultiplexer>(_ =>
            {
                var redisConfiguration = ConfigurationOptions.Parse(distributedCacheOptions.RedisConnectionString, true);
                redisConfiguration.AbortOnConnectFail = distributedCacheOptions.AbortOnConnectFail;
                redisConfiguration.ConnectRetry = distributedCacheOptions.ConnectRetry;
                redisConfiguration.ConnectTimeout = distributedCacheOptions.ConnectTimeoutMilliseconds;
                redisConfiguration.AsyncTimeout = distributedCacheOptions.AsyncTimeoutMilliseconds;
                redisConfiguration.SyncTimeout = distributedCacheOptions.SyncTimeoutMilliseconds;
                return ConnectionMultiplexer.Connect(redisConfiguration);
            });

            services.AddStackExchangeRedisCache(options =>
            {
                options.Configuration = distributedCacheOptions.RedisConnectionString;
                options.InstanceName = distributedCacheOptions.InstanceName;
            });
        }
        else if (string.Equals(distributedCacheOptions.Provider, "Memory", StringComparison.OrdinalIgnoreCase))
        {
            services.AddDistributedMemoryCache();
        }
        else
        {
            throw new InvalidOperationException($"Unsupported distributed cache provider '{distributedCacheOptions.Provider}'.");
        }

        services.AddSingleton<ITrustedGatewayReplayProtector>(serviceProvider =>
            new DistributedTrustedGatewayReplayProtector(
                serviceProvider.GetRequiredService<IDistributedCache>(),
                serviceProvider.GetRequiredService<ILogger<DistributedTrustedGatewayReplayProtector>>(),
                serviceProvider.GetService<IConnectionMultiplexer>()));

        services.AddSingleton<ITrustedGatewayRequestValidator>(serviceProvider =>
            new TrustedGatewayRequestValidator(
                serviceProvider.GetRequiredService<IOptions<TrustedGatewayOptions>>().Value,
                serviceProvider.GetRequiredService<ITrustedGatewayReplayProtector>(),
                serviceProvider.GetRequiredService<ILogger<TrustedGatewayRequestValidator>>()));

        services.AddSingleton<ITrustedGatewaySigner>(serviceProvider =>
            new TrustedGatewaySigner(serviceProvider.GetRequiredService<IOptions<TrustedGatewayOptions>>().Value));

        services.AddScoped<IAuthUnitOfWork>(serviceProvider => serviceProvider.GetRequiredService<AuthDbContext>());
        services.AddScoped<ITenantRepository, TenantRepository>();
        services.AddScoped<IUserRepository, UserRepository>();
        services.AddScoped<IUserSessionRepository, UserSessionRepository>();
        services.AddScoped<IAccessTokenFactory, JwtAccessTokenFactory>();
        services.AddScoped<IRefreshTokenService, RefreshTokenService>();
        services.AddScoped<IAuthAuditTrail, AuthAuditTrail>();
        services.AddSingleton<OutboxPayloadProtector>();
        services.AddScoped<IIntegrationEventOutbox, IntegrationEventOutbox>();
        services.AddScoped<OutboxMessagePublisher>();
        services.AddScoped<IAuthVerificationTokenRepository, AuthVerificationTokenRepository>();
        services.AddScoped<ITenantInvitationRepository, TenantInvitationRepository>();
        services.AddScoped<IInviteNotificationDispatcher>(serviceProvider =>
        {
            var deliveryOptions = serviceProvider.GetRequiredService<IOptions<InvitationDeliveryOptions>>().Value;
            if (string.Equals(deliveryOptions.Provider, "smtp", StringComparison.OrdinalIgnoreCase))
            {
                return ActivatorUtilities.CreateInstance<SmtpInviteNotificationDispatcher>(serviceProvider);
            }

            return ActivatorUtilities.CreateInstance<OutboxInviteNotificationDispatcher>(serviceProvider);
        });
        services.AddSingleton<IAuthVerificationTokenService, AuthVerificationTokenService>();
        services.AddScoped<IUserMfaRecoveryCodeRepository, UserMfaRecoveryCodeRepository>();
        services.AddScoped<ITrustedDeviceRepository, TrustedDeviceRepository>();
        services.AddScoped<IAuthAuditTrailReader, AuthAuditTrailReader>();
        services.AddScoped<IAuthenticatorKeyProtector, AuthenticatorKeyProtector>();
        services.AddSingleton<IAuthenticatorTotpService, AuthenticatorTotpService>();
        services.AddSingleton<IRecoveryCodeService, RecoveryCodeService>();
        services.AddScoped<IAuthSessionService, AuthSessionService>();
        services.AddScoped<IUserTokenStateValidator, UserTokenStateValidator>();
        services.AddScoped<IUserSessionStateValidator, UserSessionStateValidator>();
        services.AddScoped<IAccountTargetCooldownStore, AccountTargetCooldownStore>();
        services.AddScoped<DataRetentionCleanupRunner>();

        services.AddSingleton<IClock, SystemClock>();
        services.AddSingleton<ITokenSigningKeyProvider, TokenSigningKeyProvider>();
        services.AddSingleton<ISecurityAlertPublisher, SecurityAlertPublisher>();
        services.AddScoped<IPasswordHasher<User>, PasswordHasher<User>>();
        services.AddRabbitMqMessaging(configuration);
        services.AddHostedService<OutboxPublisherService>();
        services.AddHostedService<DataRetentionCleanupService>();

        services
            .AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
            .AddJwtBearer();

        services
            .AddOptions<JwtBearerOptions>(JwtBearerDefaults.AuthenticationScheme)
            .Configure<IOptions<JwtOptions>, IOptions<TokenTransportOptions>, ITokenSigningKeyProvider>(
                (options, jwtOptionsAccessor, tokenTransportAccessor, tokenSigningKeyProvider) =>
                {
                    var jwtOptions = jwtOptionsAccessor.Value;
                    var tokenTransport = tokenTransportAccessor.Value;

                    options.RequireHttpsMetadata = true;
                    options.IncludeErrorDetails = false;
                    options.SaveToken = false;
                    options.TokenValidationParameters = new TokenValidationParameters
                    {
                        ValidateIssuer = true,
                        ValidIssuer = jwtOptions.Issuer,
                        ValidateAudience = true,
                        ValidAudience = jwtOptions.Audience,
                        ValidateIssuerSigningKey = true,
                        IssuerSigningKeys = tokenSigningKeyProvider.GetValidationKeys(),
                        ValidateLifetime = true,
                        ClockSkew = TimeSpan.FromSeconds(30),
                        NameClaimType = ClaimTypes.NameIdentifier,
                        RoleClaimType = ClaimTypes.Role
                    };

                    options.Events = new JwtBearerEvents
                    {
                        OnMessageReceived = context =>
                        {
                            if (string.IsNullOrWhiteSpace(context.Token) &&
                                context.Request.Cookies.TryGetValue(tokenTransport.AccessCookieName, out var cookieToken))
                            {
                                context.Token = cookieToken;
                            }

                            return Task.CompletedTask;
                        },
                        OnTokenValidated = async context =>
                        {
                            var tenantClaim = context.Principal?.FindFirst("tenant_id")?.Value;
                            var subjectClaim = context.Principal?.FindFirst(JwtRegisteredClaimNames.Sub)?.Value ??
                                               context.Principal?.FindFirst(ClaimTypes.NameIdentifier)?.Value;
                            var sessionClaim = context.Principal?.FindFirst(JwtRegisteredClaimNames.Sid)?.Value ??
                                               context.Principal?.FindFirst(ClaimTypes.Sid)?.Value;
                            var tokenVersionClaim = context.Principal?.FindFirst("token_version")?.Value;

                            if (!Guid.TryParse(tenantClaim, out var tenantId) ||
                                !Guid.TryParse(subjectClaim, out var userId) ||
                                !Guid.TryParse(sessionClaim, out var sessionId) ||
                                !int.TryParse(tokenVersionClaim, out var tokenVersion))
                            {
                                context.Fail("JWT principal claims are incomplete.");
                                return;
                            }

                            var tokenStateValidator = context.HttpContext.RequestServices.GetRequiredService<IUserTokenStateValidator>();

                            var isValid = await tokenStateValidator.IsValidAsync(
                                tenantId,
                                userId,
                                tokenVersion,
                                context.HttpContext.RequestAborted);

                            if (!isValid)
                            {
                                context.Fail("JWT token is no longer valid.");
                                return;
                            }

                            var sessionStateValidator = context.HttpContext.RequestServices.GetRequiredService<IUserSessionStateValidator>();

                            var isSessionValid = await sessionStateValidator.IsValidAsync(
                                tenantId,
                                userId,
                                sessionId,
                                context.HttpContext.RequestAborted);

                            if (!isSessionValid)
                            {
                                context.Fail("JWT session is no longer valid.");
                            }
                        }
                    };
                });

        services.AddAuthorization();
        return services;
    }

    public static async Task InitializeAuthInfrastructureAsync(this IServiceProvider services, CancellationToken cancellationToken)
    {
        using var scope = services.CreateScope();
        var scopedServices = scope.ServiceProvider;
        var dbContext = scopedServices.GetRequiredService<AuthDbContext>();
        var databaseOptions = scopedServices.GetRequiredService<IOptions<DatabaseOptions>>().Value;
        var environment = scopedServices.GetRequiredService<IHostEnvironment>();
        var clock = scopedServices.GetRequiredService<IClock>();
        var distributedCacheOptions = scopedServices.GetRequiredService<IOptions<DistributedCacheOptions>>().Value;

        if (environment.IsProduction() &&
            string.Equals(distributedCacheOptions.Provider, "Memory", StringComparison.OrdinalIgnoreCase))
        {
            throw new InvalidOperationException(
                "In production, DistributedCache provider 'Memory' is not allowed. Configure Redis or another external provider.");
        }

        if (databaseOptions.ApplyMigrationsOnStartup && environment.IsDevelopment())
        {
            var hasMigrations = dbContext.Database.GetMigrations().Any();
            if (hasMigrations)
            {
                await dbContext.Database.MigrateAsync(cancellationToken);
            }
            else
            {
                await dbContext.Database.EnsureCreatedAsync(cancellationToken);
            }
        }

        if (!await dbContext.Database.CanConnectAsync(cancellationToken))
        {
            throw new InvalidOperationException("Identity database is unavailable during startup.");
        }

        var seedOptions = scopedServices.GetRequiredService<IOptions<SeedOptions>>().Value;
        if (!seedOptions.AllowStartupSeed ||
            (environment.IsProduction() && !seedOptions.AllowProductionStartupSeed))
        {
            return;
        }

        if (seedOptions.DefaultTenantId == Guid.Empty)
        {
            return;
        }

        var tenant = await dbContext.Tenants.SingleOrDefaultAsync(x => x.Id == seedOptions.DefaultTenantId, cancellationToken);
        if (tenant is not null)
        {
            return;
        }

        var utcNow = clock.UtcDateTime;

        dbContext.Tenants.Add(new Tenant
        {
            Id = seedOptions.DefaultTenantId,
            Name = "Default Tenant",
            Slug = "default",
            IsActive = true,
            CreatedAt = utcNow,
            UpdatedAt = utcNow
        });

        await dbContext.SaveChangesAsync(cancellationToken);
    }
}
