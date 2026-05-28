// <copyright file="DisabledEmailProvider.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using Microsoft.Extensions.Logging;
using Norge360.Notification.Infrastructure.Modules.Email.Application;

namespace Norge360.Notification.Infrastructure.Modules.Email.Infrastructure.Providers;

public sealed class DisabledEmailProvider(
    ILogger<DisabledEmailProvider> logger) : IEmailProvider
{
    public string Name => "disabled";

    public Task SendAsync(EmailMessage message, CancellationToken cancellationToken)
    {
        logger.LogWarning(
            "Email provider is disabled; notification email send skipped. Recipient={Recipient} CorrelationId={CorrelationId}",
            EmailRecipientMasker.Mask(message.To),
            message.CorrelationId);
        return Task.CompletedTask;
    }
}
