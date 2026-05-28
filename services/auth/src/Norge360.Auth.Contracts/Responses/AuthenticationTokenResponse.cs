// <copyright file="AuthenticationTokenResponse.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

namespace Norge360.Auth.Contracts.Responses;

public sealed record AuthenticationTokenResponse(
    string AccessToken,
    DateTime AccessTokenExpiresAt,
    string RefreshToken,
    DateTime RefreshTokenExpiresAt,
    Guid TenantId,
    Guid UserId,
    string UserName,
    string Email,
    Guid SessionId,
    bool IsPersistent = false);
