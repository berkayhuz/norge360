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
    IOptions<TokenTransportOptions> tokenTransportOptions,
    AuthCookieService cookieService)
{
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
        var userId = principal.FindFirstValue(ClaimTypes.NameIdentifier) ?? principal.FindFirstValue(JwtRegisteredClaimNames.Sub);
        var sessionId = principal.FindFirstValue(JwtRegisteredClaimNames.Sid);
        var email = principal.FindFirstValue(ClaimTypes.Email) ?? principal.FindFirstValue(JwtRegisteredClaimNames.Email);

        if (!Guid.TryParse(userId, out var parsedUserId) ||
            !Guid.TryParse(sessionId, out var parsedSessionId))
        {
            throw new AuthApplicationException(
                "Invalid principal context",
                "Authenticated session claims are incomplete.",
                StatusCodes.Status401Unauthorized,
                errorCode: "invalid_principal_context");
        }

        return new PrincipalContext(parsedUserId, parsedSessionId, email);
    }

    private Guid ReadSessionIdFromCookie(HttpRequest request) =>
        Guid.TryParse(request.Cookies[cookieService.SessionCookieName], out var sessionId) ? sessionId : Guid.Empty;
}

public sealed record PrincipalContext(Guid UserId, Guid CurrentSessionId, string? Email);
