// <copyright file="RabbitMqServiceCollectionExtensions.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Options;
using Norge360.Messaging.Abstractions;
using Norge360.Messaging.RabbitMq.Connection;
using Norge360.Messaging.RabbitMq.Options;
using Norge360.Messaging.RabbitMq.Publishing;

namespace Norge360.Messaging.RabbitMq.DependencyInjection;

public static class RabbitMqServiceCollectionExtensions
{
    public static IServiceCollection AddRabbitMqMessaging(this IServiceCollection services, IConfiguration configuration)
    {
        services
            .AddOptions<RabbitMqOptions>()
            .Bind(configuration.GetSection(RabbitMqOptions.SectionName))
            .ValidateDataAnnotations()
            .ValidateOnStart();

        services.AddSingleton<IValidateOptions<RabbitMqOptions>, RabbitMqOptionsValidation>();
        services.AddSingleton<RabbitMqConnectionProvider>();
        services.AddSingleton<IIntegrationEventPublisher, RabbitMqIntegrationEventPublisher>();
        return services;
    }
}
