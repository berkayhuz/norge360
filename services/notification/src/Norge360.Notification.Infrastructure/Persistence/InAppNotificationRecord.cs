// <copyright file="InAppNotificationRecord.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

namespace Norge360.Notification.Infrastructure.Persistence;

public sealed class InAppNotificationRecord
{
    private InAppNotificationRecord()
    {
        Subject = string.Empty;
        Body = string.Empty;
    }

    public InAppNotificationRecord(
        Guid id,
        Guid userId,
        string subject,
        string body,
        string? correlationId,
        DateTime createdAtUtc)
    {
        Id = id;
        UserId = userId;
        Subject = subject;
        Body = body;
        CorrelationId = correlationId;
        CreatedAtUtc = createdAtUtc;
    }

    public Guid Id { get; private set; }
    public Guid UserId { get; private set; }
    public string Subject { get; private set; }
    public string Body { get; private set; }
    public string? CorrelationId { get; private set; }
    public bool IsRead { get; private set; }
    public DateTime CreatedAtUtc { get; private set; }
    public DateTime? ReadAtUtc { get; private set; }
}
