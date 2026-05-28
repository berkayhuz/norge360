// <copyright file="AmazonSesEmailProvider.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using Amazon.SimpleEmailV2;
using Amazon.SimpleEmailV2.Model;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using MimeKit;
using Norge360.Notification.Infrastructure.Modules.Email.Application;
using Norge360.Notification.Infrastructure.Modules.Email.Infrastructure.Options;

namespace Norge360.Notification.Infrastructure.Modules.Email.Infrastructure.Providers;

public sealed class AmazonSesEmailProvider(
    IAmazonSimpleEmailServiceV2 sesClient,
    IOptions<AmazonSesEmailProviderOptions> options,
    ILogger<AmazonSesEmailProvider> logger) : IEmailProvider
{
    public string Name => "amazon-ses";

    public async Task SendAsync(EmailMessage message, CancellationToken cancellationToken)
    {
        var value = options.Value;
        var request = new SendEmailRequest
        {
            FromEmailAddress = new MailboxAddress(value.FromName, value.FromAddress).ToString(),
            Destination = new Destination
            {
                ToAddresses = [message.To]
            },
            Content = new EmailContent
            {
                Simple = new Message
                {
                    Subject = new Content
                    {
                        Charset = "UTF-8",
                        Data = message.Subject
                    },
                    Body = new Body
                    {
                        Html = new Content
                        {
                            Charset = "UTF-8",
                            Data = message.HtmlBody
                        },
                        Text = new Content
                        {
                            Charset = "UTF-8",
                            Data = message.TextBody
                        }
                    }
                }
            },
            ConfigurationSetName = string.IsNullOrWhiteSpace(value.ConfigurationSetName)
                ? null
                : value.ConfigurationSetName,
            EmailTags =
            [
                new MessageTag
                {
                    Name = "service",
                    Value = "Norge360-notification"
                }
            ]
        };

        if (!string.IsNullOrWhiteSpace(message.CorrelationId))
        {
            request.EmailTags.Add(new MessageTag
            {
                Name = "correlation-id",
                Value = NormalizeSesTagValue(message.CorrelationId)
            });
        }

        var response = await sesClient.SendEmailAsync(request, cancellationToken);
        logger.LogInformation(
            "Amazon SES accepted notification email. SesMessageId={SesMessageId} Recipient={Recipient} CorrelationId={CorrelationId}",
            response.MessageId,
            EmailRecipientMasker.Mask(message.To),
            message.CorrelationId);
    }

    private static string NormalizeSesTagValue(string value)
    {
        var normalized = new string(value
            .Where(character => char.IsLetterOrDigit(character) || character is '_' or '-' or '.')
            .Take(256)
            .ToArray());

        return string.IsNullOrWhiteSpace(normalized) ? "unknown" : normalized;
    }
}
