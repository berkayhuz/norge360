// <copyright file="AuthSessionResult.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using Norge360.Auth.Contracts.Responses;

namespace Norge360.Auth.Application.Records;

public abstract record AuthSessionResult
{
    private AuthSessionResult()
    {
    }

    public sealed record Issued(AuthenticationTokenResponse Tokens) : AuthSessionResult;

    public sealed record PendingConfirmation(Guid TenantId, Guid UserId, string Email) : AuthSessionResult;
}
