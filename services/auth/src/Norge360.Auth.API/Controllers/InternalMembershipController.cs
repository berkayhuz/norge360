// <copyright file="InternalMembershipController.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using MediatR;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Options;
using Norge360.AspNetCore.TrustedGateway.Options;
using Norge360.Auth.API.Accessors;
using Norge360.Auth.API.Security;
using Norge360.Auth.Application.Exceptions;
using Norge360.Auth.Application.Features.Commands;
using Norge360.Auth.Contracts.Internal;

namespace Norge360.Auth.API.Controllers;

[ApiController]
[Authorize(Policy = AuthAuthorizationPolicies.InternalService)]
[Route("api/v1/internal/membership/users/{userId:guid}")]
public sealed class InternalMembershipController(
    ISender sender,
    AuthRequestContextAccessor requestContextAccessor,
    IOptions<InternalIdentityOptions> internalIdentityOptions,
    IOptions<TrustedGatewayOptions> trustedGatewayOptions) : ControllerBase
{
    [HttpGet("organizations")]
    [ProducesResponseType<IReadOnlyCollection<InternalOrganizationMembershipSummaryResponse>>(StatusCodes.Status200OK)]
    public async Task<ActionResult<IReadOnlyCollection<InternalOrganizationMembershipSummaryResponse>>> ListOrganizations(
        Guid userId,
        CancellationToken cancellationToken)
    {
        var tenantId = ResolveInternalTenantId();
        return Ok(await sender.Send(new ListUserWorkspaceMembershipsCommand(tenantId, userId), cancellationToken));
    }

    [HttpGet("permissions")]
    [ProducesResponseType<InternalPermissionOverviewResponse>(StatusCodes.Status200OK)]
    public async Task<ActionResult<InternalPermissionOverviewResponse>> GetPermissions(
        Guid userId,
        [FromQuery] Guid? organizationId,
        CancellationToken cancellationToken)
    {
        var tenantId = ResolveInternalTenantId();
        return Ok(await sender.Send(new GetUserWorkspacePermissionsCommand(tenantId, userId, organizationId), cancellationToken));
    }

    private Guid ResolveInternalTenantId()
    {
        var sourceHeader = trustedGatewayOptions.Value.SourceHeaderName;
        var source = Request.Headers[sourceHeader].FirstOrDefault();
        if (!internalIdentityOptions.Value.AllowedSources.Contains(source, StringComparer.Ordinal))
        {
            throw new AuthApplicationException(
                "Internal membership caller rejected",
                "The internal membership API can only be called by an allowed service source.",
                StatusCodes.Status403Forbidden,
                errorCode: "internal_membership_source_forbidden");
        }

        return requestContextAccessor.ResolveTenantId(Guid.Empty);
    }
}
