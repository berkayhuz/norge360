// <copyright file="AuthPasswordResetRequestedV1.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

namespace Norge360.Auth.Contracts.IntegrationEvents;

public sealed record AuthPasswordResetRequestedV1(
    Guid UserId,
    Guid TenantId,
    string UserName,
    string Email,
    string Token,
    string ResetUrl,
    DateTime ExpiresAtUtc)
{
    public const string EventName = "auth.password.reset-requested";
    public const int EventVersion = 1;
    public const string RoutingKey = "auth.password.reset-requested.v1";
}
