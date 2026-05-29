// <copyright file="AuthEmailConfirmationRequestedV1.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

namespace Norge360.Auth.Contracts.IntegrationEvents;

public sealed record AuthEmailConfirmationRequestedV1(
    Guid UserId,
    string UserName,
    string Email,
    string Token,
    string ConfirmationUrl,
    DateTime ExpiresAtUtc,
    string? Culture = null)
{
    public const string EventName = "auth.email.confirmation-requested";
    public const int EventVersion = 1;
    public const string RoutingKey = "auth.email.confirmation-requested.v1";
}
