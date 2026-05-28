// <copyright file="InvitationRequests.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

namespace Norge360.Auth.Contracts.Requests;

public sealed record CreateTenantInvitationRequest(
    string Email,
    string? FirstName,
    string? LastName);

public sealed record AcceptTenantInvitationRequest(
    Guid TenantId,
    string Token,
    string UserName,
    string Email,
    string Password,
    string? FirstName,
    string? LastName);
