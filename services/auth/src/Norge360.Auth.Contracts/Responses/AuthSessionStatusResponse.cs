// <copyright file="AuthSessionStatusResponse.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

namespace Norge360.Auth.Contracts.Responses;

public sealed record AuthSessionStatusResponse(
    Guid UserId,
    Guid SessionId,
    string Email,
    IReadOnlyCollection<string> Roles,
    IReadOnlyCollection<string> Permissions,
    string AccountStatus,
    bool EmailConfirmed,
    DateTimeOffset? MfaVerifiedAt);
