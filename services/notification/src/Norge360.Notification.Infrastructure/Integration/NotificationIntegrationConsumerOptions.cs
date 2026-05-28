// <copyright file="NotificationIntegrationConsumerOptions.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using System.ComponentModel.DataAnnotations;

namespace Norge360.Notification.Infrastructure.Integration;

public sealed class NotificationIntegrationConsumerOptions
{
    public const string SectionName = "Notification:IntegrationConsumer";

    public bool Enabled { get; init; } = true;

    [Required]
    public string QueueName { get; init; } = "Norge360.notification.integration.v1";
}
