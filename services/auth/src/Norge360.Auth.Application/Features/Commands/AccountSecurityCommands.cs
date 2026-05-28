// <copyright file="AccountSecurityCommands.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using MediatR;
using Norge360.Auth.Contracts.Internal;

namespace Norge360.Auth.Application.Features.Commands;

public sealed record GetAccountSecuritySummaryQuery(Guid TenantId, Guid UserId)
    : IRequest<AccountSecuritySummaryResponse>;

public sealed record GetMfaStatusQuery(Guid TenantId, Guid UserId)
    : IRequest<MfaStatusResult>;

public sealed record SetupMfaCommand(Guid TenantId, Guid UserId, string Issuer)
    : IRequest<MfaSetupResult>;

public sealed record ConfirmMfaCommand(
    Guid TenantId,
    Guid UserId,
    string VerificationCode,
    string? IpAddress,
    string? UserAgent,
    string? CorrelationId,
    string? TraceId) : IRequest<MfaConfirmResult>;

public sealed record DisableMfaCommand(
    Guid TenantId,
    Guid UserId,
    string VerificationCode,
    string? IpAddress,
    string? UserAgent,
    string? CorrelationId,
    string? TraceId) : IRequest;

public sealed record RegenerateRecoveryCodesCommand(
    Guid TenantId,
    Guid UserId,
    string? IpAddress,
    string? UserAgent,
    string? CorrelationId,
    string? TraceId) : IRequest<RecoveryCodesResult>;

public sealed record ListTrustedDevicesQuery(Guid TenantId, Guid UserId, Guid? CurrentSessionId)
    : IRequest<TrustedDevicesIdentityResponse>;

public sealed record RevokeTrustedDeviceCommand(
    Guid TenantId,
    Guid UserId,
    Guid DeviceId,
    string? IpAddress,
    string? UserAgent,
    string? CorrelationId,
    string? TraceId) : IRequest<bool>;

public sealed record ConfirmEmailChangeForAccountCommand(
    Guid TenantId,
    Guid UserId,
    string Token,
    string? IpAddress,
    string? UserAgent,
    string? CorrelationId,
    string? TraceId) : IRequest<EmailChangeConfirmIdentityResult>;
