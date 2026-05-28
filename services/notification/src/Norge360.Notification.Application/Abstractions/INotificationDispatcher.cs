// <copyright file="INotificationDispatcher.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using Norge360.Notification.Contracts.Notifications.Requests;
using Norge360.Notification.Contracts.Notifications.Responses;

namespace Norge360.Notification.Application.Abstractions;

public interface INotificationDispatcher
{
    Task<SendNotificationResponse> SendAsync(
        SendNotificationRequest request,
        CancellationToken cancellationToken = default);
}
