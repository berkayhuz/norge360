// <copyright file="UpdateProfileCommand.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using MediatR;
using Norge360.Auth.Contracts.Responses;

namespace Norge360.Auth.Application.Features.Commands;

public sealed record UpdateProfileCommand(
    Guid TenantId,
    Guid UserId,
    string? FirstName,
    string? LastName) : IRequest<UserProfileResponse>;
