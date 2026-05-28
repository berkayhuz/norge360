// <copyright file="RabbitMqOptions.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using System.ComponentModel.DataAnnotations;

namespace Norge360.Messaging.RabbitMq.Options;

public sealed class RabbitMqOptions
{
    public const string SectionName = "Messaging:RabbitMq";

    [Required]
    public string Uri { get; set; } = "amqp://guest:guest@localhost:5672/";

    [Required]
    public string Exchange { get; set; } = "Norge360.integration";

    [Range(1, 120)]
    public int NetworkRecoveryIntervalSeconds { get; set; } = 10;

    [Range(1, 256)]
    public ushort ConsumerDispatchConcurrency { get; set; } = 4;

    [Range(1, 1024)]
    public ushort PrefetchCount { get; set; } = 16;
}
