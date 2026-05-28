// <copyright file="NotificationTemplateData.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

namespace Norge360.Notification.Contracts.Notifications.Models;

public sealed record NotificationTemplateData(
    string? TemplateKey,
    IReadOnlyDictionary<string, string> Values);
