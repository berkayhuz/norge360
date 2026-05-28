// <copyright file="UserProfileResponse.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

namespace Norge360.Auth.Contracts.Responses;

public sealed record UserProfileResponse(
    Guid UserId,
    Guid TenantId,
    string UserName,
    string Email,
    bool EmailConfirmed,
    string? FirstName,
    string? LastName,
    IReadOnlyCollection<string> Roles,
    IReadOnlyCollection<string> Permissions,
    DateTime CreatedAt,
    DateTime? LastLoginAt,
    DateTime? PasswordChangedAt);
