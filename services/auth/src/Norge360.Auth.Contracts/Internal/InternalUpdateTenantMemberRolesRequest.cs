// <copyright file="InternalUpdateTenantMemberRolesRequest.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

namespace Norge360.Auth.Contracts.Internal;

public sealed record InternalUpdateTenantMemberRolesRequest(
    Guid ActorUserId,
    IReadOnlyCollection<string> Roles);
