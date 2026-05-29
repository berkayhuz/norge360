// <copyright file="AuthController.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using MediatR;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using Norge360.Auth.API.Accessors;
using Norge360.Auth.API.Cookies;
using Norge360.Auth.API.Security;
using Norge360.Auth.Application.Exceptions;
using Norge360.Auth.Application.Features.Commands;
using Norge360.Auth.Application.Records;
using Norge360.Auth.Contracts.Requests;
using Norge360.Auth.Contracts.Responses;
using Norge360.Localization;

namespace Norge360.Auth.API.Controllers;

[ApiController]
[Route("api/auth")]
public sealed class AuthController(
    ISender sender,
    AuthRequestContextAccessor requestContextAccessor,
    AuthCookieService cookieService) : ControllerBase
{
    private static readonly AccountActionAcceptedResponse AccountActionAccepted = new(
        "If the request can be completed, instructions will be sent.");

    [HttpPost("register")]
    [AllowAnonymous]
    [EnableRateLimiting(AuthRateLimitingOptions.RegisterPolicyName)]
    [ProducesResponseType<AuthenticationTokenResponse>(StatusCodes.Status200OK)]
    [ProducesResponseType<AuthIssuedSessionResponse>(StatusCodes.Status200OK)]
    [ProducesResponseType<AccountActionAcceptedResponse>(StatusCodes.Status202Accepted)]
    public async Task<IActionResult> Register([FromBody] RegisterRequest request, CancellationToken cancellationToken)
    {
        var response = await sender.Send(
            new RegisterCommand(
                request.UserName,
                request.Email,
                request.Password,
                request.FirstName,
                request.LastName,
                Norge360Cultures.NormalizeOrDefault(request.Culture ?? HttpContext.Features.Get<Microsoft.AspNetCore.Localization.IRequestCultureFeature>()?.RequestCulture.Culture.Name),
                HttpContext.Connection.RemoteIpAddress?.ToString(),
                Request.Headers.UserAgent.ToString()),
            cancellationToken);

        if (response is AuthSessionResult.PendingConfirmation)
        {
            return Accepted(AccountActionAccepted);
        }

        var issued = (AuthSessionResult.Issued)response;
        cookieService.Apply(Response, issued.Tokens);
        return Ok(cookieService.CreateResponsePayload(issued.Tokens));
    }

    [HttpPost("login")]
    [AllowAnonymous]
    [EnableRateLimiting(AuthRateLimitingOptions.LoginPolicyName)]
    [ProducesResponseType<AuthenticationTokenResponse>(StatusCodes.Status200OK)]
    [ProducesResponseType<AuthIssuedSessionResponse>(StatusCodes.Status200OK)]
    public async Task<IActionResult> Login([FromBody] LoginRequest request, CancellationToken cancellationToken)
    {
        var response = await sender.Send(
            new LoginCommand(
                request.EmailOrUserName,
                request.Password,
                request.RememberMe,
                request.MfaCode,
                request.RecoveryCode,
                HttpContext.Connection.RemoteIpAddress?.ToString(),
                Request.Headers.UserAgent.ToString()),
            cancellationToken);

        cookieService.Apply(Response, response);
        return Ok(cookieService.CreateResponsePayload(response));
    }


    [HttpPost("refresh")]
    [AllowAnonymous]
    [EnableRateLimiting(AuthRateLimitingOptions.RefreshPolicyName)]
    [ProducesResponseType<AuthenticationTokenResponse>(StatusCodes.Status200OK)]
    [ProducesResponseType<AuthIssuedSessionResponse>(StatusCodes.Status200OK)]
    public async Task<IActionResult> Refresh([FromBody] RefreshTokenRequest request, CancellationToken cancellationToken)
    {
        var refreshContext = requestContextAccessor.ResolveRefreshContext(Request, request.SessionId, request.RefreshToken);

        var response = await sender.Send(
            new RefreshTokenCommand(
                refreshContext.SessionId,
                refreshContext.RefreshToken,
                HttpContext.Connection.RemoteIpAddress?.ToString(),
                Request.Headers.UserAgent.ToString()),
            cancellationToken);

        cookieService.Apply(Response, response);
        return Ok(cookieService.CreateResponsePayload(response));
    }

    [HttpPost("logout")]
    [AllowAnonymous]
    [EnableRateLimiting(AuthRateLimitingOptions.LogoutPolicyName)]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    public async Task<IActionResult> Logout([FromBody] LogoutRequest? request, CancellationToken cancellationToken)
    {
        var refreshContext = requestContextAccessor.ResolveRefreshContext(
            Request,
            request?.SessionId ?? Guid.Empty,
            request?.RefreshToken);
        PrincipalContext? principalContext = null;

        if (User.Identity?.IsAuthenticated == true)
        {
            principalContext = requestContextAccessor.GetPrincipalContext(User);
        }

        if (refreshContext.SessionId == Guid.Empty || string.IsNullOrWhiteSpace(refreshContext.RefreshToken))
        {
            cookieService.Clear(Response);
            return NoContent();
        }

        var sessionId = refreshContext.SessionId == Guid.Empty && principalContext is not null
            ? principalContext.CurrentSessionId
            : refreshContext.SessionId;

        if (sessionId != Guid.Empty && !string.IsNullOrWhiteSpace(refreshContext.RefreshToken))
        {
            try
            {
                await sender.Send(new LogoutCommand(sessionId, refreshContext.RefreshToken), cancellationToken);
            }
            catch (AuthApplicationException ex) when (
                ex.ErrorCode is "session_not_found" or "invalid_refresh_token")
            {
            }
        }

        cookieService.Clear(Response);
        return NoContent();
    }

    [HttpGet("session-status")]
    [Authorize]
    [ProducesResponseType<AuthSessionStatusResponse>(StatusCodes.Status200OK)]
    public IActionResult GetSessionStatus()
    {
        var principal = requestContextAccessor.GetPrincipalContext(User);
        var roles = User.Claims
            .Where(claim => claim.Type == System.Security.Claims.ClaimTypes.Role || claim.Type == "role")
            .SelectMany(claim => claim.Value.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .OrderBy(value => value, StringComparer.OrdinalIgnoreCase)
            .ToArray();
        var permissions = User.Claims
            .Where(claim => claim.Type == "permission" || claim.Type == "permissions")
            .SelectMany(claim => claim.Value.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .OrderBy(value => value, StringComparer.OrdinalIgnoreCase)
            .ToArray();

        return Ok(new AuthSessionStatusResponse(
            principal.UserId,
            principal.CurrentSessionId,
            principal.Email ?? string.Empty,
            roles,
            permissions,
            AccountStatus: "active",
            EmailConfirmed: true,
            MfaVerifiedAt: null));
    }

}
