// <copyright file="WorkspaceCommands.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using MediatR;
using Norge360.Auth.Contracts.Internal;
using Norge360.Auth.Contracts.Responses;

namespace Norge360.Auth.Application.Features.Commands;

public sealed record CreateWorkspaceCommand(
    Guid CurrentTenantId,
    Guid UserId,
    string Name,
    string? Culture,
    string? IpAddress,
    string? UserAgent,
    string? CorrelationId,
    string? TraceId) : IRequest<AuthenticationTokenResponse>;

public sealed record SwitchWorkspaceCommand(
    Guid CurrentTenantId,
    Guid TargetTenantId,
    Guid UserId,
    string? IpAddress,
    string? UserAgent,
    string? CorrelationId,
    string? TraceId) : IRequest<AuthenticationTokenResponse>;

public sealed record DeleteWorkspaceCommand(
    Guid CurrentTenantId,
    Guid TargetTenantId,
    Guid UserId,
    string? IpAddress,
    string? UserAgent,
    string? CorrelationId,
    string? TraceId) : IRequest;

public sealed record ListUserWorkspaceMembershipsCommand(
    Guid TenantId,
    Guid UserId) : IRequest<IReadOnlyCollection<InternalOrganizationMembershipSummaryResponse>>;

public sealed record GetUserWorkspacePermissionsCommand(
    Guid TenantId,
    Guid UserId,
    Guid? OrganizationId) : IRequest<InternalPermissionOverviewResponse>;
