// <copyright file="RoleManagementCommands.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using MediatR;
using Norge360.Auth.Contracts.Responses;

namespace Norge360.Auth.Application.Features.Commands;

public sealed record ListTenantMembersCommand(
    Guid TenantId,
    Guid RequestedByUserId) : IRequest<IReadOnlyCollection<TenantMemberResponse>>;

public sealed record UpdateTenantMemberRolesCommand(
    Guid TenantId,
    Guid TargetUserId,
    Guid RequestedByUserId,
    IReadOnlyCollection<string> Roles,
    string? IpAddress,
    string? UserAgent,
    string? CorrelationId,
    string? TraceId) : IRequest<TenantMemberResponse>;

public sealed record ListRoleCatalogCommand(
    Guid TenantId,
    Guid RequestedByUserId) : IRequest<IReadOnlyCollection<RoleCatalogResponse>>;
