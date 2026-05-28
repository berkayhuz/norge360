// <copyright file="InternalOrganizationMembershipSummaryResponse.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

namespace Norge360.Auth.Contracts.Internal;

public sealed record InternalOrganizationMembershipSummaryResponse(
    Guid OrganizationId,
    Guid TenantId,
    string OrganizationName,
    string? OrganizationSlug,
    string Status,
    bool IsDefault,
    DateTimeOffset JoinedAt,
    DateTimeOffset? LastPermissionRefreshAt,
    IReadOnlyCollection<string> Roles);
