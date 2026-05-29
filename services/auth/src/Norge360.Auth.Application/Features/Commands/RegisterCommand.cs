// <copyright file="RegisterCommand.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using MediatR;
using Norge360.Auth.Application.Records;

namespace Norge360.Auth.Application.Features.Commands;

public sealed record RegisterCommand(
    string UserName,
    string Email,
    string Password,
    string? FirstName,
    string? LastName,
    string? Culture,
    string? IpAddress,
    string? UserAgent) : IRequest<AuthSessionResult>;
