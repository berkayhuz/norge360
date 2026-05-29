// <copyright file="NotificationProcessor.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using System.Text.Json;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using Norge360.Notification.Application.Abstractions;
using Norge360.Notification.Application.Options;
using Norge360.Notification.Contracts.Notifications.Enums;
using Norge360.Notification.Contracts.Notifications.Models;
using Norge360.Notification.Contracts.Notifications.Requests;
using Norge360.Notification.Domain.Entities;

namespace Norge360.Notification.Application.Services;

public sealed class NotificationProcessor(
    IEnumerable<INotificationChannelSender> channelSenders,
    INotificationDeliveryLog deliveryLog,
    IOptions<NotificationDispatchOptions> options,
    NotificationMetrics metrics,
    ILogger<NotificationProcessor> logger) : INotificationProcessor
{
    private readonly IReadOnlyDictionary<NotificationChannel, INotificationChannelSender> _channelSenders =
        channelSenders.ToDictionary(sender => sender.Channel);

    public async Task ProcessAsync(
        NotificationMessage message,
        CancellationToken cancellationToken = default)
    {
        var channels = JsonSerializer.Deserialize<IReadOnlyCollection<NotificationChannel>>(message.ChannelsJson)
            ?? [];
        await deliveryLog.MarkProcessingAsync(message.Id, cancellationToken);
        var succeededChannels = await deliveryLog.GetSucceededChannelsAsync(message.Id, cancellationToken);
        var request = ToRequest(message, channels);

        logger.LogInformation(
            "Notification processing started. NotificationId={NotificationId} CorrelationId={CorrelationId}",
            message.Id,
            message.CorrelationId);

        foreach (var channel in channels.Distinct())
        {
            if (succeededChannels.Contains(channel))
            {
                logger.LogInformation(
                    "Notification channel already succeeded; skipping. NotificationId={NotificationId} Channel={Channel}",
                    message.Id,
                    channel);
                continue;
            }

            var result = await ProcessChannelAsync(channel, request, cancellationToken);
            await deliveryLog.RecordAttemptAsync(
                message.Id,
                result,
                ResolveRecipient(request, channel),
                cancellationToken);
            metrics.ChannelProcessed(channel, result.Succeeded);

            logger.LogInformation(
                "Notification channel processed. NotificationId={NotificationId} Channel={Channel} Succeeded={Succeeded} Provider={Provider} AttemptCount={AttemptCount}",
                message.Id,
                channel,
                result.Succeeded,
                result.Provider,
                result.AttemptCount);
        }
    }

    private async Task<NotificationChannelResult> ProcessChannelAsync(
        NotificationChannel channel,
        SendNotificationRequest request,
        CancellationToken cancellationToken)
    {
        if (!_channelSenders.TryGetValue(channel, out var sender))
        {
            return new NotificationChannelResult(
                channel,
                Succeeded: false,
                Provider: null,
                ExternalMessageId: null,
                ErrorCode: "channel_sender_not_registered",
                ErrorMessage: $"No notification sender is registered for channel '{channel}'.",
                AttemptCount: 0);
        }

        var dispatchOptions = options.Value;
        Exception? lastException = null;
        NotificationChannelSendResult? lastResult = null;

        for (var attempt = 1; attempt <= dispatchOptions.MaxAttempts; attempt++)
        {
            try
            {
                lastResult = await sender.SendAsync(request, cancellationToken);
                if (lastResult.Succeeded)
                {
                    return new NotificationChannelResult(
                        channel,
                        Succeeded: true,
                        sender.ProviderName,
                        lastResult.ExternalMessageId,
                        ErrorCode: null,
                        ErrorMessage: null,
                        AttemptCount: attempt);
                }

                logger.LogWarning(
                    "Notification channel send failed. Channel={Channel} Provider={Provider} Attempt={Attempt} ErrorCode={ErrorCode} CorrelationId={CorrelationId}",
                    channel,
                    sender.ProviderName,
                    attempt,
                    lastResult.ErrorCode,
                    request.CorrelationId);
            }
            catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
            {
                throw;
            }
            catch (Exception exception)
            {
                lastException = exception;
                logger.LogWarning(
                    exception,
                    "Notification channel send threw an exception. Channel={Channel} Provider={Provider} Attempt={Attempt} CorrelationId={CorrelationId}",
                    channel,
                    sender.ProviderName,
                    attempt,
                    request.CorrelationId);
            }

            if (attempt < dispatchOptions.MaxAttempts)
            {
                await DelayForAttemptAsync(attempt, dispatchOptions, cancellationToken);
            }
        }

        return new NotificationChannelResult(
            channel,
            Succeeded: false,
            sender.ProviderName,
            ExternalMessageId: null,
            ErrorCode: lastResult?.ErrorCode ?? lastException?.GetType().Name ?? "send_failed",
            ErrorMessage: lastResult?.ErrorMessage ?? lastException?.Message,
            AttemptCount: dispatchOptions.MaxAttempts);
    }

    private static Task DelayForAttemptAsync(
        int attempt,
        NotificationDispatchOptions options,
        CancellationToken cancellationToken)
    {
        if (options.RetryDelayMilliseconds <= 0)
        {
            return Task.CompletedTask;
        }

        var exponentialDelay = options.RetryDelayMilliseconds * Math.Pow(2, attempt - 1);
        var cappedDelay = Math.Min(exponentialDelay, options.MaxRetryDelaySeconds * 1000d);
        return Task.Delay(TimeSpan.FromMilliseconds(cappedDelay), cancellationToken);
    }

    private static SendNotificationRequest ToRequest(
        NotificationMessage message,
        IReadOnlyCollection<NotificationChannel> channels)
    {
        var metadata = JsonSerializer.Deserialize<IReadOnlyDictionary<string, string>>(message.MetadataJson)
            ?? new Dictionary<string, string>();

        return new SendNotificationRequest(
            new NotificationRecipient(
                message.UserId,
                message.RecipientEmailAddress,
                message.RecipientPhoneNumber,
                message.RecipientPushToken,
                message.RecipientDisplayName),
            channels,
            message.Category,
            message.Priority,
            message.Subject,
            message.TextBody,
            message.HtmlBody,
            message.TemplateKey,
            metadata,
            message.CorrelationId,
            message.IdempotencyKey);
    }

    private static string? ResolveRecipient(SendNotificationRequest request, NotificationChannel channel) =>
        channel switch
        {
            NotificationChannel.Email => request.Recipient.EmailAddress,
            NotificationChannel.Sms => request.Recipient.PhoneNumber,
            NotificationChannel.Push => request.Recipient.PushToken,
            NotificationChannel.InApp => request.Recipient.UserId?.ToString("D"),
            _ => null
        };
}
