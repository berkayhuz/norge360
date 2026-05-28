// <copyright file="RegisterRequest.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

namespace Norge360.Auth.Contracts.Requests;

public sealed record RegisterRequest(
    string TenantName,
    string UserName,
    string Email,
    string Password,
    string? FirstName,
    string? LastName,
    string? Culture = null);
