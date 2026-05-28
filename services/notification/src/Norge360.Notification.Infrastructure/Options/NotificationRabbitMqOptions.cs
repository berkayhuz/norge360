// <copyright file="NotificationRabbitMqOptions.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using System.ComponentModel.DataAnnotations;

namespace Norge360.Notification.Infrastructure.Options;

public sealed class NotificationRabbitMqOptions
{
    public const string SectionName = "Notification:RabbitMq";

    [Required]
    public string Host { get; init; } = "localhost";

    [Range(1, 65535)]
    public int Port { get; init; } = 5672;

    [Required]
    public string Username { get; init; } = "guest";

    [Required]
    public string Password { get; init; } = "guest";

    [Required]
    public string QueueName { get; init; } = "Norge360.notification.dispatch.v1";

    [Required]
    public string DeadLetterExchangeName { get; init; } = "Norge360.notification.dlx";

    [Required]
    public string DeadLetterQueueName { get; init; } = "Norge360.notification.dispatch.dlq.v1";

    [Required]
    public string DeadLetterRoutingKey { get; init; } = "notification.dispatch.dead";

    public bool UseQuorumQueue { get; init; } = true;

    [Range(1, 60)]
    public int NetworkRecoveryIntervalSeconds { get; init; } = 10;

    [Range(1, 128)]
    public ushort PrefetchCount { get; init; } = 8;

    public bool UseTls { get; init; }

    public string? SslServerName { get; init; }
}
