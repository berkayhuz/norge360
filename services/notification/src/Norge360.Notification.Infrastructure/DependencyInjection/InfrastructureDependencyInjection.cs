// <copyright file="InfrastructureDependencyInjection.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using Amazon;
using Amazon.Runtime;
using Amazon.SimpleEmailV2;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Options;
using Norge360.Messaging.RabbitMq.DependencyInjection;
using Norge360.Notification.Application.Abstractions;
using Norge360.Notification.Infrastructure.Channels;
using Norge360.Notification.Infrastructure.Integration;
using Norge360.Notification.Infrastructure.Modules.Email.Application;
using Norge360.Notification.Infrastructure.Modules.Email.Infrastructure.Options;
using Norge360.Notification.Infrastructure.Modules.Email.Infrastructure.Providers;
using Norge360.Notification.Infrastructure.Options;
using Norge360.Notification.Infrastructure.Persistence;
using Norge360.Notification.Infrastructure.Queues;

namespace Norge360.Notification.Infrastructure.DependencyInjection;

public static class InfrastructureDependencyInjection
{
    public static IServiceCollection AddNotificationInfrastructure(
        this IServiceCollection services,
        IConfiguration configuration)
    {
        services
            .AddOptions<NotificationDatabaseOptions>()
            .Bind(configuration.GetSection(NotificationDatabaseOptions.SectionName))
            .ValidateOnStart();
        services.AddSingleton<IValidateOptions<NotificationDatabaseOptions>, NotificationDatabaseOptionsValidation>();

        services
            .AddOptions<NotificationRabbitMqOptions>()
            .Bind(configuration.GetSection(NotificationRabbitMqOptions.SectionName))
            .ValidateDataAnnotations()
            .ValidateOnStart();
        services.AddSingleton<IValidateOptions<NotificationRabbitMqOptions>, NotificationRabbitMqOptionsValidation>();

        services
            .AddOptions<NotificationIntegrationConsumerOptions>()
            .Bind(configuration.GetSection(NotificationIntegrationConsumerOptions.SectionName))
            .ValidateDataAnnotations()
            .ValidateOnStart();
        services.AddSingleton<IValidateOptions<NotificationIntegrationConsumerOptions>, NotificationIntegrationConsumerOptionsValidation>();

        services
            .AddOptions<EmailProviderOptions>()
            .Bind(configuration.GetSection(EmailProviderOptions.SectionName))
            .ValidateDataAnnotations()
            .ValidateOnStart();
        services.AddSingleton<IValidateOptions<EmailProviderOptions>, NotificationEmailProviderOptionsValidation>();

        services
            .AddOptions<SmtpEmailProviderOptions>()
            .Bind(configuration.GetSection(SmtpEmailProviderOptions.SectionName))
            .ValidateOnStart();
        services.AddSingleton<IValidateOptions<SmtpEmailProviderOptions>, SmtpEmailProviderOptionsValidation>();

        services
            .AddOptions<AmazonSesEmailProviderOptions>()
            .Bind(configuration.GetSection(AmazonSesEmailProviderOptions.SectionName))
            .ValidateOnStart();
        services.AddSingleton<IValidateOptions<AmazonSesEmailProviderOptions>, AmazonSesEmailProviderOptionsValidation>();

        var connectionString = configuration.GetConnectionString("NotificationConnection")
            ?? throw new InvalidOperationException("Connection string 'NotificationConnection' is missing.");

        services.AddDbContext<NotificationDbContext>(options =>
        {
            options.UseNpgsql(connectionString, npgsqlOptions =>
            {
                npgsqlOptions.EnableRetryOnFailure(5, TimeSpan.FromSeconds(10), null);
                npgsqlOptions.MigrationsAssembly(typeof(NotificationDbContext).Assembly.FullName);
            });
        });

        services.AddSingleton<IAmazonSimpleEmailServiceV2>(serviceProvider =>
        {
            var sesOptions = serviceProvider.GetRequiredService<IOptions<AmazonSesEmailProviderOptions>>().Value;
            var clientConfig = new AmazonSimpleEmailServiceV2Config
            {
                RegionEndpoint = RegionEndpoint.GetBySystemName(sesOptions.Region)
            };

            if (!string.IsNullOrWhiteSpace(sesOptions.EndpointUrl))
            {
                clientConfig.ServiceURL = sesOptions.EndpointUrl;
            }

            if (!string.IsNullOrWhiteSpace(sesOptions.AccessKeyId) &&
                !string.IsNullOrWhiteSpace(sesOptions.SecretAccessKey))
            {
                return new AmazonSimpleEmailServiceV2Client(
                    new BasicAWSCredentials(sesOptions.AccessKeyId, sesOptions.SecretAccessKey),
                    clientConfig);
            }

            return new AmazonSimpleEmailServiceV2Client(clientConfig);
        });

        services.AddScoped<AmazonSesEmailProvider>();
        services.AddScoped<SmtpEmailProvider>();
        services.AddScoped<ConsoleEmailProvider>();
        services.AddScoped<DisabledEmailProvider>();
        services.AddScoped<IEmailProvider>(serviceProvider =>
        {
            var providerOptions = serviceProvider.GetRequiredService<IOptions<EmailProviderOptions>>().Value;
            return providerOptions.Provider.Trim().ToLowerInvariant() switch
            {
                "ses" or "amazon-ses" or "amazonses" => serviceProvider.GetRequiredService<AmazonSesEmailProvider>(),
                "smtp" => serviceProvider.GetRequiredService<SmtpEmailProvider>(),
                "console" => serviceProvider.GetRequiredService<ConsoleEmailProvider>(),
                "disabled" => serviceProvider.GetRequiredService<DisabledEmailProvider>(),
                _ => throw new InvalidOperationException($"Unsupported email provider '{providerOptions.Provider}'.")
            };
        });

        services.AddScoped<INotificationDeliveryLog, EfNotificationDeliveryLog>();
        services.AddSingleton<RabbitMqNotificationQueue>();
        services.AddSingleton<INotificationQueue>(sp => sp.GetRequiredService<RabbitMqNotificationQueue>());
        services.AddSingleton<INotificationQueueHealthCheck>(sp => sp.GetRequiredService<RabbitMqNotificationQueue>());
        services.AddScoped<ISmsProvider, UnavailableSmsProvider>();
        services.AddScoped<IPushProvider, UnavailablePushProvider>();
        services.AddScoped<INotificationChannelSender, EmailNotificationChannelSender>();
        services.AddScoped<INotificationChannelSender, SmsNotificationChannelSender>();
        services.AddScoped<INotificationChannelSender, PushNotificationChannelSender>();
        services.AddScoped<INotificationChannelSender, InAppNotificationChannelSender>();
        services.AddRabbitMqMessaging(configuration);
        services.AddHostedService<NotificationIntegrationEventConsumer>();

        return services;
    }

    public static async Task InitializeNotificationInfrastructureAsync(
        this IServiceProvider services,
        CancellationToken cancellationToken)
    {
        using var scope = services.CreateScope();
        var dbContext = scope.ServiceProvider.GetRequiredService<NotificationDbContext>();
        var databaseOptions = scope.ServiceProvider.GetRequiredService<IOptions<NotificationDatabaseOptions>>().Value;
        var environment = scope.ServiceProvider.GetRequiredService<IHostEnvironment>();

        if (databaseOptions.ApplyMigrationsOnStartup && environment.IsDevelopment())
        {
            await dbContext.Database.EnsureCreatedAsync(cancellationToken);
        }

        if (!await dbContext.Database.CanConnectAsync(cancellationToken))
        {
            throw new InvalidOperationException("Notification database is unavailable during startup.");
        }
    }
}
