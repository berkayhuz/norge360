// <copyright file="ISmsProvider.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

namespace Norge360.Notification.Infrastructure.Channels;

public interface ISmsProvider
{
    string Name { get; }

    Task<string?> SendAsync(
        string phoneNumber,
        string message,
        string? correlationId,
        CancellationToken cancellationToken);
}
