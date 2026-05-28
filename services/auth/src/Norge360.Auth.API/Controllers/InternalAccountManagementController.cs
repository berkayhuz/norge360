// <copyright file="InternalAccountManagementController.cs" company="Norge360">
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
using Norge360.Auth.Contracts.Internal;
using Norge360.Auth.Contracts.Responses;

namespace Norge360.Auth.API.Controllers;

[ApiController]
[Authorize(Policy = AuthAuthorizationPolicies.InternalService)]
[Route("api/v1/internal/account-management")]
public sealed class InternalAccountManagementController(
    ISender sender,
    AuthRequestContextAccessor requestContextAccessor,
    IOptions<InternalIdentityOptions> internalIdentityOptions,
    IOptions<TrustedGatewayOptions> trustedGatewayOptions) : ControllerBase
{
    [HttpPost("invitations")]
    [ProducesResponseType<TenantInvitationResponse>(StatusCodes.Status200OK)]
    public async Task<ActionResult<TenantInvitationResponse>> CreateInvitation(
        [FromBody] InternalCreateTenantInvitationRequest request,
        CancellationToken cancellationToken)
    {
        var tenantId = ResolveInternalTenantId();
        return Ok(await sender.Send(
            new CreateTenantInvitationCommand(
                tenantId,
                request.ActorUserId,
                request.Email,
                request.FirstName,
                request.LastName,
                HttpContext.Connection.RemoteIpAddress?.ToString(),
                Request.Headers.UserAgent.ToString(),
                RequestContextSupport.GetOrCreateCorrelationId(HttpContext),
                HttpContext.TraceIdentifier),
            cancellationToken));
    }

    [HttpGet("invitations")]
    [ProducesResponseType<IReadOnlyCollection<TenantInvitationSummaryResponse>>(StatusCodes.Status200OK)]
    public async Task<ActionResult<IReadOnlyCollection<TenantInvitationSummaryResponse>>> ListInvitations(
        [FromQuery] Guid actorUserId,
        CancellationToken cancellationToken)
    {
        var tenantId = ResolveInternalTenantId();
        return Ok(await sender.Send(new ListTenantInvitationsCommand(tenantId, actorUserId), cancellationToken));
    }

    [HttpPost("invitations/{invitationId:guid}/resend")]
    [ProducesResponseType<TenantInvitationResponse>(StatusCodes.Status200OK)]
    public async Task<ActionResult<TenantInvitationResponse>> ResendInvitation(
        Guid invitationId,
        [FromQuery] Guid actorUserId,
        CancellationToken cancellationToken)
    {
        var tenantId = ResolveInternalTenantId();
        return Ok(await sender.Send(
            new ResendTenantInvitationCommand(
                tenantId,
                invitationId,
                actorUserId,
                HttpContext.Connection.RemoteIpAddress?.ToString(),
                Request.Headers.UserAgent.ToString(),
                RequestContextSupport.GetOrCreateCorrelationId(HttpContext),
                HttpContext.TraceIdentifier),
            cancellationToken));
    }

    [HttpPost("invitations/{invitationId:guid}/revoke")]
    [ProducesResponseType<TenantInvitationResponse>(StatusCodes.Status200OK)]
    public async Task<ActionResult<TenantInvitationResponse>> RevokeInvitation(
        Guid invitationId,
        [FromQuery] Guid actorUserId,
        CancellationToken cancellationToken)
    {
        var tenantId = ResolveInternalTenantId();
        return Ok(await sender.Send(
            new RevokeTenantInvitationCommand(
                tenantId,
                invitationId,
                actorUserId,
                HttpContext.Connection.RemoteIpAddress?.ToString(),
                Request.Headers.UserAgent.ToString(),
                RequestContextSupport.GetOrCreateCorrelationId(HttpContext),
                HttpContext.TraceIdentifier),
            cancellationToken));
    }

    [HttpGet("members")]
    [ProducesResponseType<IReadOnlyCollection<TenantMemberResponse>>(StatusCodes.Status200OK)]
    public async Task<ActionResult<IReadOnlyCollection<TenantMemberResponse>>> ListMembers(
        [FromQuery] Guid actorUserId,
        CancellationToken cancellationToken)
    {
        var tenantId = ResolveInternalTenantId();
        return Ok(await sender.Send(new ListTenantMembersCommand(tenantId, actorUserId), cancellationToken));
    }

    [HttpGet("roles/catalog")]
    [ProducesResponseType<IReadOnlyCollection<RoleCatalogResponse>>(StatusCodes.Status200OK)]
    public async Task<ActionResult<IReadOnlyCollection<RoleCatalogResponse>>> ListRoleCatalog(
        [FromQuery] Guid actorUserId,
        CancellationToken cancellationToken)
    {
        var tenantId = ResolveInternalTenantId();
        return Ok(await sender.Send(new ListRoleCatalogCommand(tenantId, actorUserId), cancellationToken));
    }

    [HttpPut("members/{userId:guid}/roles")]
    [ProducesResponseType<TenantMemberResponse>(StatusCodes.Status200OK)]
    public async Task<ActionResult<TenantMemberResponse>> UpdateMemberRoles(
        Guid userId,
        [FromBody] InternalUpdateTenantMemberRolesRequest request,
        CancellationToken cancellationToken)
    {
        var tenantId = ResolveInternalTenantId();
        return Ok(await sender.Send(
            new UpdateTenantMemberRolesCommand(
                tenantId,
                userId,
                request.ActorUserId,
                request.Roles,
                HttpContext.Connection.RemoteIpAddress?.ToString(),
                Request.Headers.UserAgent.ToString(),
                RequestContextSupport.GetOrCreateCorrelationId(HttpContext),
                HttpContext.TraceIdentifier),
            cancellationToken));
    }

    private Guid ResolveInternalTenantId()
    {
        var sourceHeader = trustedGatewayOptions.Value.SourceHeaderName;
        var source = Request.Headers[sourceHeader].FirstOrDefault();
        if (!internalIdentityOptions.Value.AllowedSources.Contains(source, StringComparer.Ordinal))
        {
            throw new AuthApplicationException(
                "Internal account-management caller rejected",
                "The internal account-management API can only be called by an allowed service source.",
                StatusCodes.Status403Forbidden,
                errorCode: "internal_account_management_source_forbidden");
        }

        return requestContextAccessor.ResolveTenantId(Guid.Empty);
    }
}
