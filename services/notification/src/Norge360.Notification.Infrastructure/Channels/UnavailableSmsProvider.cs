// <copyright file="UnavailableSmsProvider.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

namespace Norge360.Notification.Infrastructure.Channels;

public sealed class UnavailableSmsProvider : ISmsProvider
{
    public string Name => "sms-provider-not-configured";

    public Task<string?> SendAsync(
        string phoneNumber,
        string message,
        string? correlationId,
        CancellationToken cancellationToken)
    {
        throw new InvalidOperationException("SMS provider is not configured for Notification service.");
    }
}
