// <copyright file="LoginCommand.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using MediatR;
using Norge360.Auth.Contracts.Responses;

namespace Norge360.Auth.Application.Features.Commands;

public sealed record LoginCommand(
    string EmailOrUserName,
    string Password,
    bool RememberMe,
    string? MfaCode,
    string? RecoveryCode,
    string? IpAddress,
    string? UserAgent) : IRequest<AuthenticationTokenResponse>;
