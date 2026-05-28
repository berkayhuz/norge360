// <copyright file="AuthRequestContextAccessor.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using Microsoft.Extensions.Options;
using Norge360.Auth.API.Cookies;
using Norge360.Auth.Application.Abstractions;
using Norge360.Auth.Application.Exceptions;
using Norge360.Auth.Application.Options;

namespace Norge360.Auth.API.Accessors;

public sealed class AuthRequestContextAccessor(
    ITenantContextAccessor tenantContextAccessor,
    IOptions<TenantResolutionOptions> tenantResolutionOptions,
    IOptions<TokenTransportOptions> tokenTransportOptions,
    AuthCookieService cookieService)
{
    public Guid ResolveTenantId(Guid bodyTenantId)
    {
        var resolvedTenantContext = tenantContextAccessor.Current;
        if (resolvedTenantContext is { IsTrusted: true, TenantId: Guid resolvedTenantId })
        {
            if (bodyTenantId != Guid.Empty && bodyTenantId != resolvedTenantId)
            {
                throw new AuthApplicationException(
                    "Tenant mismatch",
                    "Resolved tenant does not match request body tenant.",
                    StatusCodes.Status400BadRequest,
                    errorCode: "tenant_mismatch");
            }

            return resolvedTenantId;
        }

        if (!tenantResolutionOptions.Value.AllowBodyFallback || bodyTenantId == Guid.Empty)
        {
            throw new AuthApplicationException(
                "Tenant context required",
                "Tenant context could not be resolved from the trusted request surface.",
                StatusCodes.Status400BadRequest,
                errorCode: "tenant_resolution_required");
        }

        return bodyTenantId;
    }

    public (Guid SessionId, string RefreshToken) ResolveRefreshContext(HttpRequest request, Guid requestedSessionId, string? requestedRefreshToken)
    {
        var options = tokenTransportOptions.Value;
        var allowBodyTransport =
            string.Equals(options.Mode, TokenTransportModes.BodyOnly, StringComparison.OrdinalIgnoreCase) ||
            string.Equals(options.Mode, TokenTransportModes.HybridDevelopment, StringComparison.OrdinalIgnoreCase);

        var refreshToken = allowBodyTransport
            ? requestedRefreshToken
            : request.Cookies[cookieService.RefreshCookieName];

        if (string.IsNullOrWhiteSpace(refreshToken) && options.AllowRefreshTokenFromRequestBody)
        {
            refreshToken = requestedRefreshToken;
        }

        var sessionId = allowBodyTransport
            ? requestedSessionId
            : ReadSessionIdFromCookie(request);

        if (sessionId == Guid.Empty && options.AllowSessionIdFromRequestBody)
        {
            sessionId = requestedSessionId;
        }

        return (sessionId, refreshToken ?? string.Empty);
    }

    public PrincipalContext GetPrincipalContext(ClaimsPrincipal principal)
    {
        var tenantId = principal.FindFirstValue("tenant_id");
        var userId = principal.FindFirstValue(ClaimTypes.NameIdentifier) ?? principal.FindFirstValue(JwtRegisteredClaimNames.Sub);
        var sessionId = principal.FindFirstValue(JwtRegisteredClaimNames.Sid);
        var email = principal.FindFirstValue(ClaimTypes.Email) ?? principal.FindFirstValue(JwtRegisteredClaimNames.Email);

        if (!Guid.TryParse(tenantId, out var parsedTenantId) ||
            !Guid.TryParse(userId, out var parsedUserId) ||
            !Guid.TryParse(sessionId, out var parsedSessionId))
        {
            throw new AuthApplicationException(
                "Invalid principal context",
                "Authenticated session claims are incomplete.",
                StatusCodes.Status401Unauthorized,
                errorCode: "invalid_principal_context");
        }

        return new PrincipalContext(parsedTenantId, parsedUserId, parsedSessionId, email);
    }

    private Guid ReadSessionIdFromCookie(HttpRequest request) =>
        Guid.TryParse(request.Cookies[cookieService.SessionCookieName], out var sessionId) ? sessionId : Guid.Empty;
}

public sealed record PrincipalContext(Guid TenantId, Guid UserId, Guid CurrentSessionId, string? Email);
