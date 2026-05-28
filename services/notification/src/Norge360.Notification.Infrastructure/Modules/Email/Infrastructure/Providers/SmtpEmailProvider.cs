// <copyright file="SmtpEmailProvider.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using MailKit.Net.Smtp;
using MailKit.Security;
using Microsoft.Extensions.Options;
using MimeKit;
using Norge360.Notification.Infrastructure.Modules.Email.Application;
using Norge360.Notification.Infrastructure.Modules.Email.Infrastructure.Options;

namespace Norge360.Notification.Infrastructure.Modules.Email.Infrastructure.Providers;

public sealed class SmtpEmailProvider(IOptions<SmtpEmailProviderOptions> options) : IEmailProvider
{
    public string Name => "smtp";

    public async Task SendAsync(EmailMessage message, CancellationToken cancellationToken)
    {
        var value = options.Value;
        var mimeMessage = new MimeMessage();
        mimeMessage.From.Add(new MailboxAddress(value.FromName, value.FromAddress));
        mimeMessage.To.Add(MailboxAddress.Parse(message.To));
        mimeMessage.Subject = message.Subject;
        mimeMessage.Headers.Add("X-Correlation-Id", message.CorrelationId ?? string.Empty);
        mimeMessage.Body = new BodyBuilder
        {
            HtmlBody = message.HtmlBody,
            TextBody = message.TextBody
        }.ToMessageBody();

        using var client = new SmtpClient();
        var socketOptions = value.UseStartTls ? SecureSocketOptions.StartTls : SecureSocketOptions.Auto;
        await client.ConnectAsync(value.Host, value.Port, socketOptions, cancellationToken);

        if (!string.IsNullOrWhiteSpace(value.UserName) && !string.IsNullOrWhiteSpace(value.Password))
        {
            await client.AuthenticateAsync(value.UserName, value.Password, cancellationToken);
        }

        await client.SendAsync(mimeMessage, cancellationToken);
        await client.DisconnectAsync(quit: true, cancellationToken);
    }
}
