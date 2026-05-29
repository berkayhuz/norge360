// <copyright file="RabbitMqNotificationQueue.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using System.Collections.Concurrent;
using System.Text;
using System.Text.Json;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using Norge360.Notification.Application.Abstractions;
using Norge360.Notification.Domain.Entities;
using Norge360.Notification.Infrastructure.Options;
using RabbitMQ.Client;

namespace Norge360.Notification.Infrastructure.Queues;

public sealed class RabbitMqNotificationQueue(
    IOptions<NotificationRabbitMqOptions> options,
    ILogger<RabbitMqNotificationQueue> logger) : INotificationQueue, INotificationQueueHealthCheck, IAsyncDisposable, IDisposable
{
    private static readonly JsonSerializerOptions SerializerOptions = new(JsonSerializerDefaults.Web);
    private readonly SemaphoreSlim connectionLock = new(1, 1);
    private readonly ConcurrentDictionary<Guid, DeliveryLease> deliveryLeases = new();
    private IConnection? connection;
    private IChannel? consumerChannel;
    private bool disposed;

    public async Task EnqueueAsync(
        NotificationMessage message,
        CancellationToken cancellationToken = default)
    {
        var connectionValue = await GetConnectionAsync(cancellationToken);
        var channelOptions = new CreateChannelOptions(
            publisherConfirmationsEnabled: true,
            publisherConfirmationTrackingEnabled: true);

        await using var channel = await connectionValue.CreateChannelAsync(channelOptions, cancellationToken);
        await DeclareQueueAsync(channel, cancellationToken);

        var transportMessage = NotificationQueueMessage.From(message);
        var body = Encoding.UTF8.GetBytes(JsonSerializer.Serialize(transportMessage, SerializerOptions));
        var properties = new BasicProperties
        {
            AppId = "Norge360-notification",
            MessageId = message.Id.ToString("N"),
            CorrelationId = message.CorrelationId,
            Type = nameof(NotificationQueueMessage),
            ContentType = "application/json",
            ContentEncoding = "utf-8",
            Persistent = true,
            Timestamp = new AmqpTimestamp(DateTimeOffset.UtcNow.ToUnixTimeSeconds()),
            Headers = new Dictionary<string, object?>
            {
                ["idempotency_key"] = message.IdempotencyKey,
                ["notification_category"] = message.Category.ToString(),
                ["notification_priority"] = message.Priority.ToString()
            }
        };

        await channel.BasicPublishAsync(
            exchange: string.Empty,
            routingKey: options.Value.QueueName,
            mandatory: true,
            basicProperties: properties,
            body,
            cancellationToken);

        logger.LogInformation(
            "Notification message published to RabbitMQ. NotificationId={NotificationId} Queue={QueueName} CorrelationId={CorrelationId}",
            message.Id,
            options.Value.QueueName,
            message.CorrelationId);
    }

    public async Task<NotificationMessage?> DequeueAsync(CancellationToken cancellationToken)
    {
        var channel = await GetConsumerChannelAsync(cancellationToken);
        var result = await channel.BasicGetAsync(options.Value.QueueName, autoAck: false, cancellationToken);
        if (result is null)
        {
            return null;
        }

        var payload = Encoding.UTF8.GetString(result.Body.Span);
        var queueMessage = JsonSerializer.Deserialize<NotificationQueueMessage>(payload, SerializerOptions)
            ?? throw new InvalidOperationException("Notification queue message could not be deserialized.");

        var message = queueMessage.ToDomainMessage();
        deliveryLeases[message.Id] = new DeliveryLease(result.DeliveryTag, channel);
        return message;
    }

    public async Task CompleteAsync(
        NotificationMessage message,
        CancellationToken cancellationToken = default)
    {
        if (deliveryLeases.TryRemove(message.Id, out var lease))
        {
            await lease.Channel.BasicAckAsync(lease.DeliveryTag, multiple: false, cancellationToken);
        }
    }

    public async Task AbandonAsync(
        NotificationMessage message,
        bool requeue,
        CancellationToken cancellationToken = default)
    {
        if (deliveryLeases.TryRemove(message.Id, out var lease))
        {
            await lease.Channel.BasicNackAsync(lease.DeliveryTag, multiple: false, requeue, cancellationToken);
        }
    }

    public async Task<bool> CanConnectAsync(CancellationToken cancellationToken = default)
    {
        try
        {
            var connectionValue = await GetConnectionAsync(cancellationToken);
            await using var channel = await connectionValue.CreateChannelAsync(cancellationToken: cancellationToken);
            await DeclareQueueAsync(channel, cancellationToken);
            return true;
        }
        catch (Exception exception)
        {
            logger.LogWarning(exception, "RabbitMQ notification queue readiness check failed.");
            return false;
        }
    }

    public async Task<NotificationQueueSnapshot?> GetSnapshotAsync(CancellationToken cancellationToken = default)
    {
        try
        {
            var connectionValue = await GetConnectionAsync(cancellationToken);
            await using var channel = await connectionValue.CreateChannelAsync(cancellationToken: cancellationToken);
            await DeclareQueueAsync(channel, cancellationToken);

            var queue = await channel.QueueDeclarePassiveAsync(options.Value.QueueName, cancellationToken);
            var deadLetter = await channel.QueueDeclarePassiveAsync(options.Value.DeadLetterQueueName, cancellationToken);

            return new NotificationQueueSnapshot(
                queue.MessageCount,
                deadLetter.MessageCount,
                queue.ConsumerCount,
                DateTimeOffset.UtcNow);
        }
        catch (Exception exception)
        {
            logger.LogWarning(exception, "RabbitMQ queue snapshot collection failed.");
            return null;
        }
    }

    private async Task<IConnection> GetConnectionAsync(CancellationToken cancellationToken)
    {
        if (connection?.IsOpen == true)
        {
            return connection;
        }

        await connectionLock.WaitAsync(cancellationToken);
        try
        {
            if (connection?.IsOpen == true)
            {
                return connection;
            }

            var value = options.Value;
            var factory = new ConnectionFactory
            {
                HostName = value.Host,
                Port = value.Port,
                UserName = value.Username,
                Password = value.Password,
                AutomaticRecoveryEnabled = true,
                TopologyRecoveryEnabled = true,
                NetworkRecoveryInterval = TimeSpan.FromSeconds(value.NetworkRecoveryIntervalSeconds)
            };

            if (value.UseTls)
            {
                factory.Ssl.Enabled = true;
                factory.Ssl.ServerName = string.IsNullOrWhiteSpace(value.SslServerName)
                    ? value.Host
                    : value.SslServerName;
            }

            connection?.Dispose();
            connection = await factory.CreateConnectionAsync("Norge360-notification", cancellationToken);
            return connection;
        }
        finally
        {
            connectionLock.Release();
        }
    }

    private async Task<IChannel> GetConsumerChannelAsync(CancellationToken cancellationToken)
    {
        if (consumerChannel?.IsOpen == true)
        {
            return consumerChannel;
        }

        var connectionValue = await GetConnectionAsync(cancellationToken);
        consumerChannel = await connectionValue.CreateChannelAsync(cancellationToken: cancellationToken);
        await DeclareQueueAsync(consumerChannel, cancellationToken);
        await consumerChannel.BasicQosAsync(0, options.Value.PrefetchCount, global: false, cancellationToken);
        return consumerChannel;
    }

    private async Task DeclareQueueAsync(IChannel channel, CancellationToken cancellationToken)
    {
        var value = options.Value;
        await channel.ExchangeDeclareAsync(
            value.DeadLetterExchangeName,
            ExchangeType.Direct,
            durable: true,
            autoDelete: false,
            cancellationToken: cancellationToken);

        var deadLetterArguments = CreateQueueArguments(value.UseQuorumQueue);
        await channel.QueueDeclareAsync(
            value.DeadLetterQueueName,
            durable: true,
            exclusive: false,
            autoDelete: false,
            arguments: deadLetterArguments,
            cancellationToken: cancellationToken);

        await channel.QueueBindAsync(
            value.DeadLetterQueueName,
            value.DeadLetterExchangeName,
            value.DeadLetterRoutingKey,
            cancellationToken: cancellationToken);

        var queueArguments = CreateQueueArguments(value.UseQuorumQueue);
        queueArguments["x-dead-letter-exchange"] = value.DeadLetterExchangeName;
        queueArguments["x-dead-letter-routing-key"] = value.DeadLetterRoutingKey;

        await channel.QueueDeclareAsync(
            value.QueueName,
            durable: true,
            exclusive: false,
            autoDelete: false,
            arguments: queueArguments,
            cancellationToken: cancellationToken);
    }

    private static Dictionary<string, object?> CreateQueueArguments(bool useQuorumQueue)
    {
        var arguments = new Dictionary<string, object?>();
        if (useQuorumQueue)
        {
            arguments["x-queue-type"] = "quorum";
        }

        return arguments;
    }

    public void Dispose()
    {
        if (disposed)
        {
            return;
        }

        consumerChannel?.Dispose();
        connection?.Dispose();
        connectionLock.Dispose();
        disposed = true;
    }

    public async ValueTask DisposeAsync()
    {
        if (disposed)
        {
            return;
        }

        if (consumerChannel is not null)
        {
            await consumerChannel.DisposeAsync();
        }

        if (connection is not null)
        {
            await connection.DisposeAsync();
        }

        connectionLock.Dispose();
        disposed = true;
    }

    private sealed record DeliveryLease(ulong DeliveryTag, IChannel Channel);
}
