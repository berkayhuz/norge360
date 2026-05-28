// <copyright file="LogoutCommandHandler.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using System.Net;
using MediatR;
using Microsoft.AspNetCore.Http;
using Norge360.Auth.Application.Abstractions;
using Norge360.Auth.Application.Exceptions;
using Norge360.Auth.Application.Features.Commands;
using Norge360.Auth.Application.Records;
using Norge360.Clock;

namespace Norge360.Auth.Application.Features.Handlers;

public sealed class LogoutCommandHandler(
    IUserSessionRepository userSessionRepository,
    IAuthUnitOfWork unitOfWork,
    IAuthAuditTrail auditTrail,
    IRefreshTokenService refreshTokenService,
    IUserSessionStateValidator userSessionStateValidator,
    IClock clock,
    IHttpContextAccessor httpContextAccessor)
    : IRequestHandler<LogoutCommand, Unit>
{
    public async Task<Unit> Handle(LogoutCommand request, CancellationToken cancellationToken)
    {
        var httpContext = httpContextAccessor.HttpContext;
        var correlationId = httpContext?.Items[AspNetCore.RequestContext.RequestContextSupport.CorrelationIdHeaderName]?.ToString();
        var traceId = httpContext?.TraceIdentifier;

        var session = await userSessionRepository.GetAsync(request.TenantId, request.SessionId, cancellationToken)
            ?? throw new AuthApplicationException("Session not found", "Session could not be resolved.", (int)HttpStatusCode.NotFound, errorCode: "session_not_found");

        if (session.IsRevoked)
        {
            userSessionStateValidator.Evict(request.TenantId, request.SessionId);
            return Unit.Value;
        }

        if (!refreshTokenService.Verify(request.RefreshToken, session.RefreshTokenHash))
        {
            throw new AuthApplicationException("Invalid refresh token", "Session could not be revoked.", (int)HttpStatusCode.Unauthorized, errorCode: "invalid_refresh_token");
        }

        session.Revoke(clock.UtcDateTime, "logout");
        await auditTrail.WriteAsync(
            new AuthAuditRecord(
                request.TenantId,
                "auth.logout.succeeded",
                "success",
                session.UserId,
                session.Id,
                null,
                session.IpAddress,
                session.UserAgent,
                correlationId,
                traceId),
            cancellationToken);
        await unitOfWork.SaveChangesAsync(cancellationToken);
        userSessionStateValidator.Evict(request.TenantId, session.Id);
        return Unit.Value;
    }
}
