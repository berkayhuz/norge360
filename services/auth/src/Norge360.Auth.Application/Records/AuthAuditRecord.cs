// <copyright file="AuthAuditRecord.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

namespace Norge360.Auth.Application.Records;

public sealed record AuthAuditRecord(
    Guid TenantId,
    string EventType,
    string Outcome,
    Guid? UserId,
    Guid? SessionId,
    string? Identity,
    string? IpAddress,
    string? UserAgent,
    string? CorrelationId,
    string? TraceId,
    string? Metadata = null);
