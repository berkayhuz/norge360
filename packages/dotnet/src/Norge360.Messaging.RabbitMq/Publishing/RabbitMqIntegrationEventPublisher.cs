// <copyright file="RabbitMqIntegrationEventPublisher.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using System.Text;
using Microsoft.Extensions.Logging;
using Norge360.Messaging.Abstractions;
using Norge360.Messaging.RabbitMq.Connection;
using RabbitMQ.Client;

namespace Norge360.Messaging.RabbitMq.Publishing;

public sealed class RabbitMqIntegrationEventPublisher(
    RabbitMqConnectionProvider connectionProvider,
    ILogger<RabbitMqIntegrationEventPublisher> logger) : IIntegrationEventPublisher
{
    public async Task PublishAsync(
        string exchange,
        string routingKey,
        IntegrationMessage message,
        CancellationToken cancellationToken)
    {
        var connection = await connectionProvider.GetConnectionAsync(cancellationToken);
        var channelOptions = new CreateChannelOptions(
            publisherConfirmationsEnabled: true,
            publisherConfirmationTrackingEnabled: true);

        await using var channel = await connection.CreateChannelAsync(channelOptions, cancellationToken);
        await channel.ExchangeDeclareAsync(
            exchange,
            ExchangeType.Topic,
            durable: true,
            autoDelete: false,
            cancellationToken: cancellationToken);

        var metadata = message.Metadata;
        var properties = new BasicProperties
        {
            AppId = metadata.Source,
            MessageId = metadata.EventId.ToString("N"),
            CorrelationId = metadata.CorrelationId,
            Type = metadata.EventName,
            ContentType = "application/json",
            ContentEncoding = "utf-8",
            Persistent = true,
            Timestamp = new AmqpTimestamp(new DateTimeOffset(metadata.OccurredAtUtc).ToUnixTimeSeconds()),
            Headers = new Dictionary<string, object?>
            {
                ["event_id"] = metadata.EventId.ToString("N"),
                ["event_name"] = metadata.EventName,
                ["event_version"] = metadata.EventVersion,
                ["source"] = metadata.Source,
                ["trace_id"] = metadata.TraceId
            }
        };

        var body = Encoding.UTF8.GetBytes(message.Payload);
        await channel.BasicPublishAsync(
            exchange,
            routingKey,
            mandatory: true,
            basicProperties: properties,
            body,
            cancellationToken);

        if (logger.IsEnabled(LogLevel.Information))
        {
            logger.LogInformation(
                "Published integration event {EventName} v{EventVersion}. EventId={EventId} Exchange={Exchange} RoutingKey={RoutingKey}",
                metadata.EventName,
                metadata.EventVersion,
                metadata.EventId,
                exchange,
                routingKey);
        }
    }
}
