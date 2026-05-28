// <copyright file="WorkspaceSummaryResponse.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

namespace Norge360.Auth.Contracts.Responses;

public sealed record WorkspaceSummaryResponse(
    Guid TenantId,
    string Name,
    string? Slug,
    string? Role,
    bool IsDefault,
    DateTimeOffset? LastUsedAt);
