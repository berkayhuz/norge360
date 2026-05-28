// <copyright file="ConfirmEmailCommand.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using MediatR;

namespace Norge360.Auth.Application.Features.Commands;

public sealed record ConfirmEmailCommand(
    Guid TenantId,
    Guid UserId,
    string Token,
    string? IpAddress,
    string? UserAgent,
    string? CorrelationId,
    string? TraceId) : IRequest;
