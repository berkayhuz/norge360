// <copyright file="RefreshTokenCommandHandler.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using System.Net;
using MediatR;
using Microsoft.AspNetCore.Http;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using Norge360.AspNetCore.RequestContext;
using Norge360.Auth.Application.Abstractions;
using Norge360.Auth.Application.Diagnostics;
using Norge360.Auth.Application.Exceptions;
using Norge360.Auth.Application.Features.Commands;
using Norge360.Auth.Application.Helpers;
using Norge360.Auth.Application.Options;
using Norge360.Auth.Application.Records;
using Norge360.Auth.Contracts.Responses;
using Norge360.Clock;

namespace Norge360.Auth.Application.Features.Handlers;

public sealed class RefreshTokenCommandHandler(
    ITenantRepository tenantRepository,
    IUserRepository userRepository,
    IUserSessionRepository userSessionRepository,
    IAuthUnitOfWork unitOfWork,
    IAuthAuditTrail auditTrail,
    IAccessTokenFactory accessTokenFactory,
    IRefreshTokenService refreshTokenService,
    IClock clock,
    IAuthSessionService authSessionService,
    ISecurityAlertPublisher securityAlertPublisher,
    IUserTokenStateValidator userTokenStateValidator,
    IUserSessionStateValidator userSessionStateValidator,
    IHttpContextAccessor httpContextAccessor,
    IOptions<AccountLifecycleOptions> lifecycleOptions)
    : IRequestHandler<RefreshTokenCommand, AuthenticationTokenResponse>
{
    public async Task<AuthenticationTokenResponse> Handle(RefreshTokenCommand request, CancellationToken cancellationToken)
    {
        var httpContext = httpContextAccessor.HttpContext;
        var correlationId = httpContext?.Items[RequestContextSupport.CorrelationIdHeaderName]?.ToString();
        var traceId = httpContext?.TraceIdentifier;

        var tenant = await tenantRepository.GetByIdAsync(request.TenantId, cancellationToken)
            ?? throw InvalidRefreshToken();

        if (!tenant.IsActive)
        {
            AuthMetrics.RefreshFailed.Add(1, new KeyValuePair<string, object?>("reason", "inactive_tenant"));
            throw InvalidRefreshToken();
        }

        var session = await userSessionRepository.GetWithUserAsync(request.TenantId, request.SessionId, cancellationToken)
            ?? throw InvalidRefreshToken();

        if (session.IsRevoked || authSessionService.IsExpired(session, clock.UtcDateTime))
        {
            AuthMetrics.RefreshFailed.Add(1, new KeyValuePair<string, object?>("reason", "revoked_or_expired_session"));
            throw InvalidRefreshToken();
        }

        var ipAddress = AuthenticationNormalization.CleanOrNull(request.IpAddress);
        var userAgent = AuthenticationNormalization.CleanOrNull(request.UserAgent);

        if (!refreshTokenService.Verify(request.RefreshToken, session.RefreshTokenHash))
        {
            await HandleRefreshTokenReuseAsync(request, session, ipAddress, userAgent, correlationId, traceId, cancellationToken);
            AuthMetrics.RefreshFailed.Add(1, new KeyValuePair<string, object?>("reason", "refresh_token_reuse"));
            AuthMetrics.RefreshReuseDetected.Add(1);
            throw InvalidRefreshToken();
        }

        var user = session.User ?? await userRepository.GetByIdAsync(request.TenantId, session.UserId, cancellationToken)
            ?? throw InvalidRefreshToken();
        var membership = await userRepository.GetMembershipAsync(request.TenantId, user.Id, cancellationToken)
            ?? throw InvalidRefreshToken();

        if (!user.IsActive || user.IsDeleted)
        {
            AuthMetrics.RefreshFailed.Add(1, new KeyValuePair<string, object?>("reason", "inactive_user"));
            throw InvalidRefreshToken();
        }

        if (lifecycleOptions.Value.RequireConfirmedEmailForLogin && !user.EmailConfirmed)
        {
            session.Revoke(clock.UtcDateTime, "email_confirmation_required");
            await unitOfWork.SaveChangesAsync(cancellationToken);
            userSessionStateValidator.Evict(request.TenantId, session.Id);
            AuthMetrics.RefreshFailed.Add(1, new KeyValuePair<string, object?>("reason", "email_confirmation_required"));
            throw InvalidRefreshToken();
        }

        if (!membership.IsActive || membership.IsDeleted)
        {
            AuthMetrics.RefreshFailed.Add(1, new KeyValuePair<string, object?>("reason", "inactive_membership"));
            throw InvalidRefreshToken();
        }

        if (user.MfaEnabled && (user.MfaEnabledAt.HasValue && session.CreatedAt < user.MfaEnabledAt.Value))
        {
            session.Revoke(clock.UtcDateTime, "mfa_reauthentication_required");
            await unitOfWork.SaveChangesAsync(cancellationToken);
            userSessionStateValidator.Evict(request.TenantId, session.Id);
            AuthMetrics.RefreshFailed.Add(1, new KeyValuePair<string, object?>("reason", "mfa_reauthentication_required"));
            throw InvalidRefreshToken();
        }

        var utcNow = clock.UtcDateTime;
        var refreshToken = refreshTokenService.Generate(session.IsPersistent);

        session.RefreshTokenHash = refreshToken.Hash;
        session.RefreshTokenExpiresAt = refreshToken.ExpiresAtUtc;
        session.MarkRefreshRotated(utcNow);
        session.IpAddress = ipAddress ?? session.IpAddress;
        session.UserAgent = userAgent ?? session.UserAgent;

        await auditTrail.WriteAsync(
            new AuthAuditRecord(
                request.TenantId,
                "auth.refresh.succeeded",
                "success",
                user.Id,
                session.Id,
                user.Email,
                session.IpAddress,
                session.UserAgent,
                correlationId,
                traceId),
            cancellationToken);

        try
        {
            await unitOfWork.SaveChangesAsync(cancellationToken);
        }
        catch (DbUpdateConcurrencyException)
        {
            AuthMetrics.RefreshFailed.Add(1, new KeyValuePair<string, object?>("reason", "concurrency_conflict"));
            throw InvalidRefreshToken();
        }

        AuthMetrics.RefreshSucceeded.Add(1);

        var accessToken = accessTokenFactory.Create(
            user.Id,
            user.UserName,
            user.Email ?? string.Empty,
            user.TokenVersion,
            membership.GetRoles(),
            membership.GetPermissions(),
            tenant.Id,
            session.Id,
            new DateTimeOffset(session.CreatedAt, TimeSpan.Zero),
            user.MfaEnabled ? ["pwd", "mfa"] : ["pwd"]);

        return new AuthenticationTokenResponse(
            accessToken.Token,
            accessToken.ExpiresAtUtc,
            refreshToken.Token,
            refreshToken.ExpiresAtUtc,
            tenant.Id,
            user.Id,
            user.UserName,
            user.Email ?? string.Empty,
            session.Id,
            session.IsPersistent);
    }

    private async Task HandleRefreshTokenReuseAsync(
        RefreshTokenCommand request,
        Norge360.Auth.Domain.Entities.UserSession session,
        string? ipAddress,
        string? userAgent,
        string? correlationId,
        string? traceId,
        CancellationToken cancellationToken)
    {
        var userForReuse = await userRepository.GetByIdAsync(request.TenantId, session.UserId, cancellationToken);
        var utcNowForReuse = clock.UtcDateTime;
        IReadOnlyCollection<Guid> revokedSessionIds = [];

        session.MarkRefreshTokenReuse(utcNowForReuse, "refresh_token_reuse_detected");

        if (userForReuse is not null)
        {
            userForReuse.TokenVersion += 1;
            userForReuse.UpdatedAt = utcNowForReuse;

            revokedSessionIds = await userSessionRepository.RevokeAllAsync(
                request.TenantId,
                userForReuse.Id,
                utcNowForReuse,
                "refresh_token_reuse_detected",
                session.Id,
                cancellationToken);
        }

        await auditTrail.WriteAsync(
            new AuthAuditRecord(
                request.TenantId,
                "auth.refresh.reuse-detected",
                "revoked",
                userForReuse?.Id ?? session.UserId,
                session.Id,
                userForReuse?.Email,
                ipAddress,
                userAgent,
                correlationId,
                traceId),
            cancellationToken);

        await securityAlertPublisher.PublishAsync(
            new SecurityAlert(
                "auth.refresh-reuse",
                "critical",
                "Refresh token reuse detected; session family revoked.",
                request.TenantId,
                userForReuse?.Id ?? session.UserId,
                session.Id,
                correlationId,
                traceId),
            cancellationToken);

        await unitOfWork.SaveChangesAsync(cancellationToken);

        if (userForReuse is not null)
        {
            userTokenStateValidator.Evict(request.TenantId, userForReuse.Id);
        }

        userSessionStateValidator.Evict(request.TenantId, session.Id);
        foreach (var sessionId in revokedSessionIds)
        {
            userSessionStateValidator.Evict(request.TenantId, sessionId);
        }
    }

    private static AuthApplicationException InvalidRefreshToken() =>
        new("Invalid refresh token", "Session could not be refreshed.", (int)HttpStatusCode.Unauthorized, errorCode: "invalid_refresh_token");

}
