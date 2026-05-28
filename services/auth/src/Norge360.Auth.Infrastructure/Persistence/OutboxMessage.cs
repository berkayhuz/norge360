// <copyright file="OutboxMessage.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

namespace Norge360.Auth.Infrastructure.Persistence;

public sealed class OutboxMessage
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid EventId { get; set; }
    public string EventName { get; set; } = null!;
    public int EventVersion { get; set; }
    public string Source { get; set; } = null!;
    public string RoutingKey { get; set; } = null!;
    public string Payload { get; set; } = null!;
    public string? CorrelationId { get; set; }
    public string? TraceId { get; set; }
    public DateTime OccurredAtUtc { get; set; }
    public DateTime CreatedAtUtc { get; set; }
    public DateTime? PublishedAtUtc { get; set; }
    public int Attempts { get; set; }
    public DateTime? NextAttemptAtUtc { get; set; }
    public string? LastError { get; set; }
    public Guid? LockId { get; set; }
    public DateTime? LockedUntilUtc { get; set; }
    public byte[] RowVersion { get; set; } = [];
}
