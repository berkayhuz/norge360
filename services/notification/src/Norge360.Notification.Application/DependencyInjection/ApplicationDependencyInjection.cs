// <copyright file="ApplicationDependencyInjection.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using Microsoft.Extensions.DependencyInjection;
using Norge360.Notification.Application.Abstractions;
using Norge360.Notification.Application.Options;
using Norge360.Notification.Application.Services;

namespace Norge360.Notification.Application.DependencyInjection;

public static class ApplicationDependencyInjection
{
    public static IServiceCollection AddNotificationApplication(this IServiceCollection services)
    {
        services
            .AddOptions<NotificationDispatchOptions>()
            .BindConfiguration(NotificationDispatchOptions.SectionName)
            .ValidateDataAnnotations()
            .ValidateOnStart();

        services.AddScoped<INotificationDispatcher, NotificationDispatcher>();
        services.AddScoped<INotificationProcessor, NotificationProcessor>();
        services.AddScoped<INotificationTemplateRenderer, SimpleNotificationTemplateRenderer>();
        services.AddScoped<INotificationChannelPolicy, DefaultNotificationChannelPolicy>();
        services.AddScoped<IUserNotificationPreferenceReader, AllowAllNotificationPreferenceReader>();
        services.AddSingleton<NotificationMetrics>();
        return services;
    }
}
