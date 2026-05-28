// <copyright file="UserRegisteredV1.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

namespace Norge360.Auth.Contracts.IntegrationEvents;

public sealed record UserRegisteredV1(
    Guid UserId,
    Guid TenantId,
    string UserName,
    string Email,
    string? FirstName,
    string? LastName,
    DateTime RegisteredAtUtc,
    string? Culture = null)
{
    public const string EventName = "auth.user.registered";
    public const int EventVersion = 1;
    public const string RoutingKey = "auth.user.registered.v1";
}
