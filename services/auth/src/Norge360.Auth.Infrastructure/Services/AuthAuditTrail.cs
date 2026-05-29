// <copyright file="AuthAuditTrail.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using Microsoft.Extensions.Logging;
using Norge360.Auth.Application.Abstractions;
using Norge360.Auth.Application.Records;
using Norge360.Auth.Domain.Entities;
using Norge360.Auth.Infrastructure.Persistence;

namespace Norge360.Auth.Infrastructure.Services;

public sealed class AuthAuditTrail(AuthDbContext dbContext, ILogger<AuthAuditTrail> logger) : IAuthAuditTrail
{
    public async Task WriteAsync(AuthAuditRecord record, CancellationToken cancellationToken)
    {
        logger.LogInformation(
            "AUDIT_EVENT EventType={EventType} Outcome={Outcome} UserId={UserId} CorrelationId={CorrelationId}",
            record.EventType,
            record.Outcome,
            record.UserId,
            record.CorrelationId);

        await dbContext.AuthAuditEvents.AddAsync(new AuthAuditEvent
        {
            UserId = record.UserId,
            SessionId = record.SessionId,
            EventType = record.EventType,
            Outcome = record.Outcome,
            Identity = MaskIdentity(record.Identity),
            IpAddress = record.IpAddress,
            UserAgent = record.UserAgent,
            CorrelationId = record.CorrelationId,
            TraceId = record.TraceId,
            Metadata = record.Metadata
        }, cancellationToken);
    }

    private static string? MaskIdentity(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return value;
        }

        var index = value.IndexOf('@');
        if (index <= 1)
        {
            return "***";
        }

        return $"{value[0]}***{value[index..]}";
    }
}
