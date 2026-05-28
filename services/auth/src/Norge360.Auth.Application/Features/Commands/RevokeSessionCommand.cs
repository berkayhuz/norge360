// <copyright file="RevokeSessionCommand.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using MediatR;

namespace Norge360.Auth.Application.Features.Commands;

public sealed record RevokeSessionCommand(
    Guid TenantId,
    Guid UserId,
    Guid CurrentSessionId,
    Guid SessionId,
    string? Email,
    string? IpAddress,
    string? UserAgent,
    string? CorrelationId,
    string? TraceId) : IRequest<bool>;
