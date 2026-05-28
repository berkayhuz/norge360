// <copyright file="INotificationTemplateRenderer.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using Norge360.Notification.Contracts.Notifications.Requests;

namespace Norge360.Notification.Application.Abstractions;

public interface INotificationTemplateRenderer
{
    SendNotificationRequest Render(SendNotificationRequest request);
}
