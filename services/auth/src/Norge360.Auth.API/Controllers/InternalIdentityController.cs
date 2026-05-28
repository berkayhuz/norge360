// <copyright file="InternalIdentityController.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using MediatR;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Options;
using Norge360.AspNetCore.RequestContext;
using Norge360.AspNetCore.TrustedGateway.Options;
using Norge360.Auth.API.Accessors;
using Norge360.Auth.API.Security;
using Norge360.Auth.Application.Exceptions;
using Norge360.Auth.Application.Features.Commands;
using Norge360.Auth.Application.Options;
using Norge360.Auth.Contracts.Internal;

namespace Norge360.Auth.API.Controllers;

[ApiController]
[Authorize(Policy = AuthAuthorizationPolicies.InternalService)]
[Route("api/v1/internal/identity/users/{userId:guid}")]
public sealed class InternalIdentityController(
    ISender sender,
    AuthRequestContextAccessor requestContextAccessor,
    IOptions<JwtOptions> jwtOptions,
    IOptions<InternalIdentityOptions> internalIdentityOptions,
    IOptions<TrustedGatewayOptions> trustedGatewayOptions) : ControllerBase
{
    [HttpGet("security-summary")]
    [ProducesResponseType<AccountSecuritySummaryResponse>(StatusCodes.Status200OK)]
    public async Task<ActionResult<AccountSecuritySummaryResponse>> GetSecuritySummary(Guid userId, CancellationToken cancellationToken)
    {
        var tenantId = ResolveInternalTenantId();
        return Ok(await sender.Send(new GetAccountSecuritySummaryQuery(tenantId, userId), cancellationToken));
    }

    [HttpPost("password/change")]
    [ProducesResponseType<ChangePasswordIdentityResult>(StatusCodes.Status200OK)]
    public async Task<ActionResult<ChangePasswordIdentityResult>> ChangePassword(
        Guid userId,
        [FromBody] ChangePasswordIdentityRequest request,
        CancellationToken cancellationToken)
    {
        var tenantId = ResolveInternalTenantId();

        try
        {
            await sender.Send(
                new ChangePasswordCommand(
                    tenantId,
                    userId,
                    request.CurrentPassword,
                    request.NewPassword,
                    request.RevokeOtherSessions,
                    ExcludedSessionId: null,
                    HttpContext.Connection.RemoteIpAddress?.ToString(),
                    Request.Headers.UserAgent.ToString(),
                    RequestContextSupport.GetOrCreateCorrelationId(HttpContext),
                    HttpContext.TraceIdentifier),
                cancellationToken);

            return Ok(new ChangePasswordIdentityResult(true, []));
        }
        catch (AuthApplicationException exception) when (IsClientFailure(exception))
        {
            return Ok(new ChangePasswordIdentityResult(false, [new PasswordPolicyFailure(exception.ErrorCode ?? "password_change_failed", exception.Message)]));
        }
    }

    [HttpGet("mfa")]
    [ProducesResponseType<MfaStatusResult>(StatusCodes.Status200OK)]
    public async Task<ActionResult<MfaStatusResult>> GetMfa(Guid userId, CancellationToken cancellationToken)
    {
        var tenantId = ResolveInternalTenantId();
        return Ok(await sender.Send(new GetMfaStatusQuery(tenantId, userId), cancellationToken));
    }

    [HttpPost("mfa/setup")]
    [ProducesResponseType<MfaSetupResult>(StatusCodes.Status200OK)]
    public async Task<ActionResult<MfaSetupResult>> SetupMfa(Guid userId, CancellationToken cancellationToken)
    {
        var tenantId = ResolveInternalTenantId();
        return Ok(await sender.Send(new SetupMfaCommand(tenantId, userId, jwtOptions.Value.Issuer), cancellationToken));
    }

    [HttpPost("mfa/confirm")]
    [ProducesResponseType<MfaConfirmResult>(StatusCodes.Status200OK)]
    public async Task<ActionResult<MfaConfirmResult>> ConfirmMfa(
        Guid userId,
        [FromBody] MfaConfirmRequest request,
        CancellationToken cancellationToken)
    {
        var tenantId = ResolveInternalTenantId();
        return Ok(await sender.Send(
            new ConfirmMfaCommand(
                tenantId,
                userId,
                request.VerificationCode,
                HttpContext.Connection.RemoteIpAddress?.ToString(),
                Request.Headers.UserAgent.ToString(),
                RequestContextSupport.GetOrCreateCorrelationId(HttpContext),
                HttpContext.TraceIdentifier),
            cancellationToken));
    }

    [HttpDelete("mfa")]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    public async Task<IActionResult> DisableMfa(
        Guid userId,
        [FromBody] MfaDisableRequest request,
        CancellationToken cancellationToken)
    {
        var tenantId = ResolveInternalTenantId();
        await sender.Send(
            new DisableMfaCommand(
                tenantId,
                userId,
                request.VerificationCode,
                HttpContext.Connection.RemoteIpAddress?.ToString(),
                Request.Headers.UserAgent.ToString(),
                RequestContextSupport.GetOrCreateCorrelationId(HttpContext),
                HttpContext.TraceIdentifier),
            cancellationToken);

        return NoContent();
    }

    [HttpPost("mfa/recovery-codes/regenerate")]
    [ProducesResponseType<RecoveryCodesResult>(StatusCodes.Status200OK)]
    public async Task<ActionResult<RecoveryCodesResult>> RegenerateRecoveryCodes(Guid userId, CancellationToken cancellationToken)
    {
        var tenantId = ResolveInternalTenantId();
        return Ok(await sender.Send(
            new RegenerateRecoveryCodesCommand(
                tenantId,
                userId,
                HttpContext.Connection.RemoteIpAddress?.ToString(),
                Request.Headers.UserAgent.ToString(),
                RequestContextSupport.GetOrCreateCorrelationId(HttpContext),
                HttpContext.TraceIdentifier),
            cancellationToken));
    }

    [HttpPost("email/change-request")]
    [ProducesResponseType<EmailChangeRequestIdentityResult>(StatusCodes.Status200OK)]
    public async Task<ActionResult<EmailChangeRequestIdentityResult>> RequestEmailChange(
        Guid userId,
        [FromBody] EmailChangeRequestIdentityRequest request,
        CancellationToken cancellationToken)
    {
        var tenantId = ResolveInternalTenantId();

        try
        {
            await sender.Send(
                new ChangeEmailCommand(
                    tenantId,
                    userId,
                    request.NewEmail,
                    CurrentEmail: string.Empty,
                    request.CurrentPassword,
                    HttpContext.Connection.RemoteIpAddress?.ToString(),
                    Request.Headers.UserAgent.ToString(),
                    RequestContextSupport.GetOrCreateCorrelationId(HttpContext),
                    HttpContext.TraceIdentifier),
                cancellationToken);

            return Ok(new EmailChangeRequestIdentityResult(true, []));
        }
        catch (AuthApplicationException exception) when (IsClientFailure(exception))
        {
            return Ok(new EmailChangeRequestIdentityResult(false, [new PasswordPolicyFailure(exception.ErrorCode ?? "email_change_failed", exception.Message)]));
        }
    }

    [HttpPost("email/change-confirm")]
    [ProducesResponseType<EmailChangeConfirmIdentityResult>(StatusCodes.Status200OK)]
    public async Task<ActionResult<EmailChangeConfirmIdentityResult>> ConfirmEmailChange(
        Guid userId,
        [FromBody] EmailChangeConfirmIdentityRequest request,
        CancellationToken cancellationToken)
    {
        var tenantId = ResolveInternalTenantId();
        return Ok(await sender.Send(
            new ConfirmEmailChangeForAccountCommand(
                tenantId,
                userId,
                request.Token,
                HttpContext.Connection.RemoteIpAddress?.ToString(),
                Request.Headers.UserAgent.ToString(),
                RequestContextSupport.GetOrCreateCorrelationId(HttpContext),
                HttpContext.TraceIdentifier),
            cancellationToken));
    }

    [HttpGet("trusted-devices")]
    [ProducesResponseType<TrustedDevicesIdentityResponse>(StatusCodes.Status200OK)]
    public async Task<ActionResult<TrustedDevicesIdentityResponse>> GetTrustedDevices(Guid userId, CancellationToken cancellationToken)
    {
        var tenantId = ResolveInternalTenantId();
        return Ok(await sender.Send(new ListTrustedDevicesQuery(tenantId, userId, CurrentSessionId: null), cancellationToken));
    }

    [HttpDelete("trusted-devices/{deviceId:guid}")]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<IActionResult> RevokeTrustedDevice(Guid userId, Guid deviceId, CancellationToken cancellationToken)
    {
        var tenantId = ResolveInternalTenantId();
        var revoked = await sender.Send(
            new RevokeTrustedDeviceCommand(
                tenantId,
                userId,
                deviceId,
                HttpContext.Connection.RemoteIpAddress?.ToString(),
                Request.Headers.UserAgent.ToString(),
                RequestContextSupport.GetOrCreateCorrelationId(HttpContext),
                HttpContext.TraceIdentifier),
            cancellationToken);

        return revoked ? NoContent() : NotFound();
    }

    private static bool IsClientFailure(AuthApplicationException exception) =>
        exception.StatusCode is >= StatusCodes.Status400BadRequest and < StatusCodes.Status500InternalServerError;

    private Guid ResolveInternalTenantId()
    {
        var sourceHeader = trustedGatewayOptions.Value.SourceHeaderName;
        var source = Request.Headers[sourceHeader].FirstOrDefault();
        if (!internalIdentityOptions.Value.AllowedSources.Contains(source, StringComparer.Ordinal))
        {
            throw new AuthApplicationException(
                "Internal identity caller rejected",
                "The internal identity API can only be called by an allowed service source.",
                StatusCodes.Status403Forbidden,
                errorCode: "internal_identity_source_forbidden");
        }

        return requestContextAccessor.ResolveTenantId(Guid.Empty);
    }
}
