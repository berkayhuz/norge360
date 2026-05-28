// <copyright file="IIntegrationEventPublisher.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

namespace Norge360.Messaging.Abstractions;

public interface IIntegrationEventPublisher
{
    Task PublishAsync(
        string exchange,
        string routingKey,
        IntegrationMessage message,
        CancellationToken cancellationToken);
}
