// <copyright file="InvitationResponses.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

namespace Norge360.Auth.Contracts.Responses;

public sealed record TenantInvitationResponse(
    Guid TenantId,
    Guid InvitationId,
    string Email,
    DateTime ExpiresAtUtc,
    string Status,
    DateTime? LastSentAtUtc);

public sealed record TenantInvitationSummaryResponse(
    Guid TenantId,
    Guid InvitationId,
    string Email,
    string? FirstName,
    string? LastName,
    DateTime ExpiresAtUtc,
    string Status,
    int ResendCount,
    DateTime CreatedAtUtc,
    DateTime? LastSentAtUtc,
    DateTime? AcceptedAtUtc,
    DateTime? RevokedAtUtc,
    string? LastDeliveryStatus);
