// <copyright file="NotificationIntegrationEventConsumer.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using System.Text;
using System.Text.Json;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using Norge360.Auth.Contracts.IntegrationEvents;
using Norge360.Messaging.RabbitMq.Connection;
using Norge360.Messaging.RabbitMq.Options;
using Norge360.Notification.Application.Abstractions;
using Norge360.Notification.Contracts.IntegrationEvents.V1;
using Norge360.Notification.Contracts.Notifications.Enums;
using Norge360.Notification.Contracts.Notifications.Models;
using Norge360.Notification.Contracts.Notifications.Requests;
using RabbitMQ.Client;
using RabbitMQ.Client.Events;

namespace Norge360.Notification.Infrastructure.Integration;

public sealed class NotificationIntegrationEventConsumer(
    IServiceScopeFactory scopeFactory,
    RabbitMqConnectionProvider connectionProvider,
    IOptions<RabbitMqOptions> rabbitMqOptions,
    IOptions<NotificationIntegrationConsumerOptions> options,
    ILogger<NotificationIntegrationEventConsumer> logger) : BackgroundService
{
    private static readonly JsonSerializerOptions SerializerOptions = new(JsonSerializerDefaults.Web);

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        if (!options.Value.Enabled)
        {
            logger.LogInformation("Notification integration consumer is disabled.");
            return;
        }

        var rabbitOptions = rabbitMqOptions.Value;
        var consumerOptions = options.Value;
        var connection = await connectionProvider.GetConnectionAsync(stoppingToken);
        await using var channel = await connection.CreateChannelAsync(cancellationToken: stoppingToken);

        await channel.ExchangeDeclareAsync(
            rabbitOptions.Exchange,
            ExchangeType.Topic,
            durable: true,
            autoDelete: false,
            cancellationToken: stoppingToken);

        await channel.QueueDeclareAsync(
            consumerOptions.QueueName,
            durable: true,
            exclusive: false,
            autoDelete: false,
            cancellationToken: stoppingToken);

        foreach (var routingKey in GetRoutingKeys())
        {
            await channel.QueueBindAsync(
                consumerOptions.QueueName,
                rabbitOptions.Exchange,
                routingKey,
                cancellationToken: stoppingToken);
        }

        await channel.BasicQosAsync(0, rabbitOptions.PrefetchCount, global: false, cancellationToken: stoppingToken);

        var consumer = new AsyncEventingBasicConsumer(channel);
        consumer.ReceivedAsync += async (_, eventArgs) =>
        {
            try
            {
                await ProcessAsync(
                    Encoding.UTF8.GetString(eventArgs.Body.Span),
                    eventArgs.RoutingKey,
                    eventArgs.BasicProperties,
                    stoppingToken);

                await channel.BasicAckAsync(eventArgs.DeliveryTag, multiple: false, cancellationToken: stoppingToken);
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                await channel.BasicNackAsync(eventArgs.DeliveryTag, multiple: false, requeue: true, cancellationToken: CancellationToken.None);
            }
            catch (Exception exception)
            {
                logger.LogError(
                    exception,
                    "Notification integration event processing failed. RoutingKey={RoutingKey} MessageId={MessageId}",
                    eventArgs.RoutingKey,
                    eventArgs.BasicProperties.MessageId);
                await channel.BasicNackAsync(eventArgs.DeliveryTag, multiple: false, requeue: false, cancellationToken: stoppingToken);
            }
        };

        await channel.BasicConsumeAsync(consumerOptions.QueueName, autoAck: false, consumer, stoppingToken);
        logger.LogInformation("Notification integration consumer started. Queue={QueueName}", consumerOptions.QueueName);
        await Task.Delay(Timeout.InfiniteTimeSpan, stoppingToken);
    }

    private async Task ProcessAsync(
        string payload,
        string routingKey,
        IReadOnlyBasicProperties properties,
        CancellationToken cancellationToken)
    {
        using var scope = scopeFactory.CreateScope();
        var dispatcher = scope.ServiceProvider.GetRequiredService<INotificationDispatcher>();
        var request = MapToRequest(payload, routingKey, properties);
        await dispatcher.SendAsync(request, cancellationToken);

        logger.LogInformation(
            "Notification integration event accepted. RoutingKey={RoutingKey} MessageId={MessageId} CorrelationId={CorrelationId}",
            routingKey,
            properties.MessageId,
            properties.CorrelationId);
    }

    private static SendNotificationRequest MapToRequest(
        string payload,
        string routingKey,
        IReadOnlyBasicProperties properties)
    {
        var eventId = properties.MessageId ?? Guid.NewGuid().ToString("N");
        var correlationId = properties.CorrelationId;

        return routingKey switch
        {
            NotificationRequestedV1.RoutingKey => FromNotificationRequested(payload, correlationId, eventId),
            SecurityNotificationRequestedV1.RoutingKey => FromSecurityNotificationRequested(payload, correlationId, eventId),
            CrmReminderNotificationRequestedV1.RoutingKey => FromCrmReminderRequested(payload, correlationId, eventId),
            TaskNotificationRequestedV1.RoutingKey => FromTaskNotificationRequested(payload, correlationId, eventId),
            AuthEmailConfirmationRequestedV1.RoutingKey => FromAuthEmailConfirmation(payload, correlationId, eventId),
            AuthPasswordResetRequestedV1.RoutingKey => FromAuthPasswordReset(payload, correlationId, eventId),
            AuthEmailChangeRequestedV1.RoutingKey => FromAuthEmailChange(payload, correlationId, eventId),
            UserRegisteredV1.RoutingKey => FromUserRegistered(payload, correlationId, eventId),
            "account.security_notification.requested.v1" => FromAccountSecurityNotification(payload, correlationId, eventId),
            _ => throw new InvalidOperationException($"Unsupported notification integration routing key '{routingKey}'.")
        };
    }

    private static SendNotificationRequest FromNotificationRequested(string payload, string? correlationId, string eventId)
    {
        var message = JsonSerializer.Deserialize<NotificationRequestedV1>(payload, SerializerOptions)
            ?? throw new InvalidOperationException("NotificationRequestedV1 payload could not be deserialized.");
        return new SendNotificationRequest(
            message.Recipient,
            message.Channels,
            message.Category,
            message.Priority,
            message.Subject,
            message.TextBody,
            message.HtmlBody,
            message.Template.TemplateKey,
            MergeMetadata(message.Metadata, message.Template.Values),
            message.CorrelationId ?? correlationId,
            message.IdempotencyKey ?? eventId);
    }

    private static SendNotificationRequest FromSecurityNotificationRequested(string payload, string? correlationId, string eventId)
    {
        var message = JsonSerializer.Deserialize<SecurityNotificationRequestedV1>(payload, SerializerOptions)
            ?? throw new InvalidOperationException("SecurityNotificationRequestedV1 payload could not be deserialized.");
        return new SendNotificationRequest(
            message.Recipient,
            message.Channels,
            NotificationCategory.Security,
            NotificationPriority.Critical,
            message.Subject,
            message.TextBody,
            message.HtmlBody,
            message.Template.TemplateKey,
            MergeMetadata(message.Metadata, message.Template.Values, ("securityEventType", message.SecurityEventType)),
            message.CorrelationId ?? correlationId,
            message.IdempotencyKey ?? eventId);
    }

    private static SendNotificationRequest FromCrmReminderRequested(string payload, string? correlationId, string eventId)
    {
        var message = JsonSerializer.Deserialize<CrmReminderNotificationRequestedV1>(payload, SerializerOptions)
            ?? throw new InvalidOperationException("CrmReminderNotificationRequestedV1 payload could not be deserialized.");
        return new SendNotificationRequest(
            message.Recipient,
            message.Channels,
            NotificationCategory.CrmReminder,
            NotificationPriority.High,
            message.Subject,
            message.TextBody,
            message.HtmlBody,
            message.Template.TemplateKey,
            MergeMetadata(message.Metadata, message.Template.Values, ("reminderType", message.ReminderType)),
            message.CorrelationId ?? correlationId,
            message.IdempotencyKey ?? eventId);
    }

    private static SendNotificationRequest FromTaskNotificationRequested(string payload, string? correlationId, string eventId)
    {
        var message = JsonSerializer.Deserialize<TaskNotificationRequestedV1>(payload, SerializerOptions)
            ?? throw new InvalidOperationException("TaskNotificationRequestedV1 payload could not be deserialized.");
        return new SendNotificationRequest(
            message.Recipient,
            message.Channels,
            NotificationCategory.Task,
            NotificationPriority.Normal,
            message.Subject,
            message.TextBody,
            message.HtmlBody,
            message.Template.TemplateKey,
            MergeMetadata(message.Metadata, message.Template.Values, ("taskId", message.TaskId.ToString("D")), ("taskTitle", message.TaskTitle)),
            message.CorrelationId ?? correlationId,
            message.IdempotencyKey ?? eventId);
    }

    private static SendNotificationRequest FromAuthEmailConfirmation(string payload, string? correlationId, string eventId)
    {
        var message = JsonSerializer.Deserialize<AuthEmailConfirmationRequestedV1>(payload, SerializerOptions)
            ?? throw new InvalidOperationException("AuthEmailConfirmationRequestedV1 payload could not be deserialized.");
        return SecurityEmail(message.UserId, message.UserName, message.Email, "Confirm your Norge360 email", "Confirm your email: {{ActionUrl}}", "auth.email-confirmation", message.ConfirmationUrl, correlationId, eventId, message.Culture);
    }

    private static SendNotificationRequest FromAuthPasswordReset(string payload, string? correlationId, string eventId)
    {
        var message = JsonSerializer.Deserialize<AuthPasswordResetRequestedV1>(payload, SerializerOptions)
            ?? throw new InvalidOperationException("AuthPasswordResetRequestedV1 payload could not be deserialized.");
        return SecurityEmail(message.UserId, message.UserName, message.Email, "Reset your Norge360 password", "Reset your password: {{ActionUrl}}", "auth.password-reset", message.ResetUrl, correlationId, eventId);
    }

    private static SendNotificationRequest FromAuthEmailChange(string payload, string? correlationId, string eventId)
    {
        var message = JsonSerializer.Deserialize<AuthEmailChangeRequestedV1>(payload, SerializerOptions)
            ?? throw new InvalidOperationException("AuthEmailChangeRequestedV1 payload could not be deserialized.");
        return SecurityEmail(message.UserId, message.UserName, message.NewEmail, "Confirm your new Norge360 email", "Confirm your new email: {{ActionUrl}}", "auth.email-change-confirmation", message.ConfirmationUrl, correlationId, eventId);
    }

    private static SendNotificationRequest FromUserRegistered(string payload, string? correlationId, string eventId)
    {
        var message = JsonSerializer.Deserialize<UserRegisteredV1>(payload, SerializerOptions)
            ?? throw new InvalidOperationException("UserRegisteredV1 payload could not be deserialized.");
        var displayName = string.IsNullOrWhiteSpace(message.FirstName) ? message.UserName : message.FirstName;
        return new SendNotificationRequest(
            new NotificationRecipient(message.UserId, message.Email, null, null, displayName),
            [NotificationChannel.Email, NotificationChannel.InApp],
            NotificationCategory.Account,
            NotificationPriority.Normal,
            "Welcome to Norge360",
            "Hello {{displayName}}, your Norge360 account is ready.",
            "<p>Hello {{displayName}}, your Norge360 account is ready.</p>",
            "auth.user_registered.v1",
            new Dictionary<string, string> { ["displayName"] = displayName, ["culture"] = message.Culture ?? string.Empty },
            correlationId,
            eventId);
    }

    private static SendNotificationRequest FromAccountSecurityNotification(string payload, string? correlationId, string eventId)
    {
        using var document = JsonDocument.Parse(payload);
        var root = document.RootElement;
        var userId = GetProperty(root, "userId").GetGuid();
        var notificationType = GetProperty(root, "notificationType").GetString() ?? "security_event";
        return new SendNotificationRequest(
            new NotificationRecipient(userId, null, null, null, null),
            [NotificationChannel.InApp],
            NotificationCategory.Security,
            NotificationPriority.Critical,
            "Security notification",
            "A security event occurred: {{securityEventType}}.",
            null,
            "account.security_notification.v1",
            new Dictionary<string, string> { ["securityEventType"] = notificationType },
            correlationId,
            eventId);
    }

    private static SendNotificationRequest SecurityEmail(Guid userId, string userName, string email, string subject, string textBody, string templateKey, string url, string? correlationId, string eventId, string? culture = null) =>
        new(
            new NotificationRecipient(userId, email, null, null, userName),
            [NotificationChannel.Email],
            NotificationCategory.Security,
            NotificationPriority.Critical,
            subject,
            textBody,
            "<p>" + textBody + "</p>",
            templateKey,
            new Dictionary<string, string>
            {
                ["displayName"] = userName,
                ["DisplayName"] = userName,
                ["ActionUrl"] = url,
                ["url"] = url,
                ["culture"] = culture ?? string.Empty
            },
            correlationId,
            eventId);

    private static IReadOnlyDictionary<string, string> MergeMetadata(
        IReadOnlyDictionary<string, string> metadata,
        IReadOnlyDictionary<string, string> templateValues,
        params (string Key, string Value)[] extra)
    {
        var merged = new Dictionary<string, string>(metadata, StringComparer.OrdinalIgnoreCase);
        foreach (var pair in templateValues)
        {
            merged[pair.Key] = pair.Value;
        }

        foreach (var pair in extra)
        {
            merged[pair.Key] = pair.Value;
        }

        return merged;
    }

    private static string[] GetRoutingKeys() =>
    [
        NotificationRequestedV1.RoutingKey,
        SecurityNotificationRequestedV1.RoutingKey,
        CrmReminderNotificationRequestedV1.RoutingKey,
        TaskNotificationRequestedV1.RoutingKey,
        AuthEmailConfirmationRequestedV1.RoutingKey,
        AuthPasswordResetRequestedV1.RoutingKey,
        AuthEmailChangeRequestedV1.RoutingKey,
        UserRegisteredV1.RoutingKey,
        "account.security_notification.requested.v1"
    ];

    private static JsonElement GetProperty(JsonElement element, string name)
    {
        if (element.TryGetProperty(name, out var value))
        {
            return value;
        }

        var pascalName = char.ToUpperInvariant(name[0]) + name[1..];
        return element.TryGetProperty(pascalName, out value)
            ? value
            : throw new InvalidOperationException($"Required property '{name}' was not found.");
    }
}
