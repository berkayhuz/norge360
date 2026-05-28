// <copyright file="UnavailablePushProvider.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

namespace Norge360.Notification.Infrastructure.Channels;

public sealed class UnavailablePushProvider : IPushProvider
{
    public string Name => "push-provider-not-configured";

    public Task<string?> SendAsync(
        string pushToken,
        string title,
        string body,
        string? correlationId,
        CancellationToken cancellationToken)
    {
        throw new InvalidOperationException("Push provider is not configured for Notification service.");
    }
}
