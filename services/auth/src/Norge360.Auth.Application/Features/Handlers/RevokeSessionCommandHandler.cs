// <copyright file="RevokeSessionCommandHandler.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using MediatR;
using Norge360.Auth.Application.Abstractions;
using Norge360.Auth.Application.Features.Commands;
using Norge360.Auth.Application.Records;
using Norge360.Clock;

namespace Norge360.Auth.Application.Features.Handlers;

public sealed class RevokeSessionCommandHandler(
    IUserSessionRepository userSessionRepository,
    IUserSessionStateValidator userSessionStateValidator,
    IAuthAuditTrail auditTrail,
    IAuthUnitOfWork unitOfWork,
    IClock clock) : IRequestHandler<RevokeSessionCommand, bool>
{
    public async Task<bool> Handle(RevokeSessionCommand request, CancellationToken cancellationToken)
    {
        var revoked = await userSessionRepository.RevokeAsync(
            request.TenantId,
            request.UserId,
            request.SessionId,
            clock.UtcDateTime,
            request.SessionId == request.CurrentSessionId
                ? "user_revoked_current_session"
                : "user_revoked_session",
            cancellationToken);

        if (!revoked)
        {
            return false;
        }

        await auditTrail.WriteAsync(
            new AuthAuditRecord(
                request.TenantId,
                "auth.session.revoked",
                "success",
                request.UserId,
                request.SessionId,
                request.Email,
                request.IpAddress,
                request.UserAgent,
                request.CorrelationId,
                request.TraceId),
            cancellationToken);

        await unitOfWork.SaveChangesAsync(cancellationToken);
        userSessionStateValidator.Evict(request.TenantId, request.SessionId);
        return true;
    }
}
