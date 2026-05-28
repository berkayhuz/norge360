// <copyright file="RevokeOtherSessionsCommandHandler.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using MediatR;
using Norge360.Auth.Application.Abstractions;
using Norge360.Auth.Application.Features.Commands;
using Norge360.Auth.Application.Records;
using Norge360.Clock;

namespace Norge360.Auth.Application.Features.Handlers;

public sealed class RevokeOtherSessionsCommandHandler(
    IUserSessionRepository userSessionRepository,
    IUserSessionStateValidator userSessionStateValidator,
    IAuthAuditTrail auditTrail,
    IAuthUnitOfWork unitOfWork,
    IClock clock) : IRequestHandler<RevokeOtherSessionsCommand, Unit>
{
    public async Task<Unit> Handle(RevokeOtherSessionsCommand request, CancellationToken cancellationToken)
    {
        var revokedSessionIds = await userSessionRepository.RevokeAllAsync(
            request.TenantId,
            request.UserId,
            clock.UtcDateTime,
            "user_revoked_other_sessions",
            request.CurrentSessionId,
            cancellationToken);

        await auditTrail.WriteAsync(
            new AuthAuditRecord(
                request.TenantId,
                "auth.session.revoke-others",
                "success",
                request.UserId,
                request.CurrentSessionId,
                request.Email,
                request.IpAddress,
                request.UserAgent,
                request.CorrelationId,
                request.TraceId),
            cancellationToken);

        await unitOfWork.SaveChangesAsync(cancellationToken);

        foreach (var sessionId in revokedSessionIds)
        {
            userSessionStateValidator.Evict(request.TenantId, sessionId);
        }

        return Unit.Value;
    }
}
