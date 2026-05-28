// <copyright file="ConsoleEmailProvider.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using Microsoft.Extensions.Logging;
using Norge360.Notification.Infrastructure.Modules.Email.Application;

namespace Norge360.Notification.Infrastructure.Modules.Email.Infrastructure.Providers;

public sealed class ConsoleEmailProvider(
    ILogger<ConsoleEmailProvider> logger) : IEmailProvider
{
    public string Name => "console";

    public Task SendAsync(EmailMessage message, CancellationToken cancellationToken)
    {
        logger.LogInformation(
            "Console email provider accepted notification email. Recipient={Recipient} Subject={Subject} CorrelationId={CorrelationId}",
            EmailRecipientMasker.Mask(message.To),
            message.Subject,
            message.CorrelationId);
        return Task.CompletedTask;
    }
}
