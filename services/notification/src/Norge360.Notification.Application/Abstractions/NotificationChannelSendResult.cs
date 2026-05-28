// <copyright file="NotificationChannelSendResult.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

namespace Norge360.Notification.Application.Abstractions;

public sealed record NotificationChannelSendResult(
    bool Succeeded,
    string? ExternalMessageId,
    string? ErrorCode,
    string? ErrorMessage);
