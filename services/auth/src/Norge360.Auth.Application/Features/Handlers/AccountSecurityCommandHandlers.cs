// <copyright file="AccountSecurityCommandHandlers.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using System.Net;
using MediatR;
using Norge360.Auth.Application.Abstractions;
using Norge360.Auth.Application.Exceptions;
using Norge360.Auth.Application.Features.Commands;
using Norge360.Auth.Application.Records;
using Norge360.Auth.Contracts.Internal;
using Norge360.Auth.Domain.Entities;
using Norge360.Clock;

namespace Norge360.Auth.Application.Features.Handlers;

public sealed class GetAccountSecuritySummaryQueryHandler(IUserRepository users, IAuthAuditTrailReader auditTrailReader)
    : IRequestHandler<GetAccountSecuritySummaryQuery, AccountSecuritySummaryResponse>
{
    public async Task<AccountSecuritySummaryResponse> Handle(GetAccountSecuritySummaryQuery request, CancellationToken cancellationToken)
    {
        var user = await users.GetByIdAsync(request.TenantId, request.UserId, cancellationToken) ?? throw NotFound();
        var lastSecurityEventAt = await auditTrailReader.GetLastSecurityEventAtAsync(request.TenantId, request.UserId, cancellationToken);
        return new AccountSecuritySummaryResponse(user.MfaEnabled, lastSecurityEventAt);
    }

    private static AuthApplicationException NotFound() =>
        new("User not found", "User could not be found.", (int)HttpStatusCode.NotFound, errorCode: "user_not_found");
}

public sealed class GetMfaStatusQueryHandler(
    IUserRepository users,
    IUserMfaRecoveryCodeRepository recoveryCodes)
    : IRequestHandler<GetMfaStatusQuery, MfaStatusResult>
{
    public async Task<MfaStatusResult> Handle(GetMfaStatusQuery request, CancellationToken cancellationToken)
    {
        var user = await users.GetByIdAsync(request.TenantId, request.UserId, cancellationToken) ?? throw NotFound();
        var activeCodes = await recoveryCodes.CountActiveAsync(request.TenantId, request.UserId, cancellationToken);
        return new MfaStatusResult(user.MfaEnabled, !string.IsNullOrWhiteSpace(user.AuthenticatorKeyProtected), activeCodes);
    }

    private static AuthApplicationException NotFound() =>
        new("User not found", "User could not be found.", (int)HttpStatusCode.NotFound, errorCode: "user_not_found");
}

public sealed class SetupMfaCommandHandler(
    IUserRepository users,
    IAuthenticatorTotpService totpService,
    IAuthenticatorKeyProtector keyProtector,
    IAuthUnitOfWork unitOfWork,
    IClock clock)
    : IRequestHandler<SetupMfaCommand, MfaSetupResult>
{
    public async Task<MfaSetupResult> Handle(SetupMfaCommand request, CancellationToken cancellationToken)
    {
        var user = await users.GetByIdAsync(request.TenantId, request.UserId, cancellationToken) ?? throw NotFound();
        var sharedKey = totpService.GenerateSharedKey();

        user.AuthenticatorKeyProtected = keyProtector.Protect(sharedKey);
        user.AuthenticatorKeyCreatedAt = clock.UtcDateTime;
        user.AuthenticatorKeyConfirmedAt = null;
        user.UpdatedAt = clock.UtcDateTime;

        await unitOfWork.SaveChangesAsync(cancellationToken);

        var accountName = string.IsNullOrWhiteSpace(user.Email) ? user.UserName : user.Email;
        return new MfaSetupResult(sharedKey, totpService.BuildAuthenticatorUri(request.Issuer, accountName, sharedKey));
    }

    private static AuthApplicationException NotFound() =>
        new("User not found", "User could not be found.", (int)HttpStatusCode.NotFound, errorCode: "user_not_found");
}

public sealed class ConfirmMfaCommandHandler(
    IUserRepository users,
    IAuthenticatorTotpService totpService,
    IAuthenticatorKeyProtector keyProtector,
    IRecoveryCodeService recoveryCodeService,
    IUserMfaRecoveryCodeRepository recoveryCodeRepository,
    IAuthAuditTrail auditTrail,
    IAuthUnitOfWork unitOfWork,
    IUserTokenStateValidator tokenStateValidator,
    IClock clock)
    : IRequestHandler<ConfirmMfaCommand, MfaConfirmResult>
{
    public async Task<MfaConfirmResult> Handle(ConfirmMfaCommand request, CancellationToken cancellationToken)
    {
        var user = await users.GetByIdAsync(request.TenantId, request.UserId, cancellationToken) ?? throw NotFound();
        if (string.IsNullOrWhiteSpace(user.AuthenticatorKeyProtected))
        {
            throw new AuthApplicationException("MFA setup required", "Authenticator setup has not been started.", (int)HttpStatusCode.BadRequest, errorCode: "mfa_setup_required");
        }

        var sharedKey = keyProtector.Unprotect(user.AuthenticatorKeyProtected);
        if (!totpService.VerifyCode(sharedKey, request.VerificationCode, clock.UtcDateTime))
        {
            throw new AuthApplicationException("Invalid MFA code", "The supplied authenticator code is invalid.", (int)HttpStatusCode.BadRequest, errorCode: "invalid_mfa_code");
        }

        var utcNow = clock.UtcDateTime;
        var rawCodes = recoveryCodeService.GenerateCodes(10);
        var entities = rawCodes
            .Select(code => new UserMfaRecoveryCode
            {
                TenantId = request.TenantId,
                UserId = request.UserId,
                CodeHash = recoveryCodeService.HashCode(request.TenantId, request.UserId, code),
                CreatedAt = utcNow
            })
            .ToArray();

        user.MfaEnabled = true;
        user.MfaEnabledAt = utcNow;
        user.AuthenticatorKeyConfirmedAt = utcNow;
        user.RecoveryCodesGeneratedAt = utcNow;
        user.SecurityStamp = Guid.NewGuid().ToString("N");
        user.TokenVersion++;
        user.UpdatedAt = utcNow;

        await recoveryCodeRepository.ReplaceActiveAsync(request.TenantId, request.UserId, entities, utcNow, cancellationToken);
        await auditTrail.WriteAsync(new AuthAuditRecord(request.TenantId, "auth.mfa.enabled", "success", request.UserId, null, user.Email, request.IpAddress, request.UserAgent, request.CorrelationId, request.TraceId), cancellationToken);
        await unitOfWork.SaveChangesAsync(cancellationToken);
        tokenStateValidator.Evict(request.TenantId, request.UserId);

        return new MfaConfirmResult(true, rawCodes);
    }

    private static AuthApplicationException NotFound() =>
        new("User not found", "User could not be found.", (int)HttpStatusCode.NotFound, errorCode: "user_not_found");
}

public sealed class DisableMfaCommandHandler(
    IUserRepository users,
    IAuthenticatorTotpService totpService,
    IAuthenticatorKeyProtector keyProtector,
    IUserMfaRecoveryCodeRepository recoveryCodeRepository,
    IAuthAuditTrail auditTrail,
    IAuthUnitOfWork unitOfWork,
    IUserTokenStateValidator tokenStateValidator,
    IClock clock)
    : IRequestHandler<DisableMfaCommand>
{
    public async Task Handle(DisableMfaCommand request, CancellationToken cancellationToken)
    {
        var user = await users.GetByIdAsync(request.TenantId, request.UserId, cancellationToken) ?? throw NotFound();
        if (string.IsNullOrWhiteSpace(user.AuthenticatorKeyProtected))
        {
            return;
        }

        var sharedKey = keyProtector.Unprotect(user.AuthenticatorKeyProtected);
        if (!totpService.VerifyCode(sharedKey, request.VerificationCode, clock.UtcDateTime))
        {
            throw new AuthApplicationException("Invalid MFA code", "The supplied authenticator code is invalid.", (int)HttpStatusCode.BadRequest, errorCode: "invalid_mfa_code");
        }

        var utcNow = clock.UtcDateTime;
        user.MfaEnabled = false;
        user.MfaEnabledAt = null;
        user.AuthenticatorKeyProtected = null;
        user.AuthenticatorKeyCreatedAt = null;
        user.AuthenticatorKeyConfirmedAt = null;
        user.SecurityStamp = Guid.NewGuid().ToString("N");
        user.TokenVersion++;
        user.UpdatedAt = utcNow;

        await recoveryCodeRepository.RevokeActiveAsync(request.TenantId, request.UserId, utcNow, cancellationToken);
        await auditTrail.WriteAsync(new AuthAuditRecord(request.TenantId, "auth.mfa.disabled", "success", request.UserId, null, user.Email, request.IpAddress, request.UserAgent, request.CorrelationId, request.TraceId), cancellationToken);
        await unitOfWork.SaveChangesAsync(cancellationToken);
        tokenStateValidator.Evict(request.TenantId, request.UserId);
    }

    private static AuthApplicationException NotFound() =>
        new("User not found", "User could not be found.", (int)HttpStatusCode.NotFound, errorCode: "user_not_found");
}

public sealed class RegenerateRecoveryCodesCommandHandler(
    IUserRepository users,
    IRecoveryCodeService recoveryCodeService,
    IUserMfaRecoveryCodeRepository recoveryCodeRepository,
    IAuthAuditTrail auditTrail,
    IAuthUnitOfWork unitOfWork,
    IClock clock)
    : IRequestHandler<RegenerateRecoveryCodesCommand, RecoveryCodesResult>
{
    public async Task<RecoveryCodesResult> Handle(RegenerateRecoveryCodesCommand request, CancellationToken cancellationToken)
    {
        var user = await users.GetByIdAsync(request.TenantId, request.UserId, cancellationToken) ?? throw NotFound();
        if (!user.MfaEnabled)
        {
            throw new AuthApplicationException("MFA is disabled", "Recovery codes can only be generated when MFA is enabled.", (int)HttpStatusCode.BadRequest, errorCode: "mfa_disabled");
        }

        var utcNow = clock.UtcDateTime;
        var rawCodes = recoveryCodeService.GenerateCodes(10);
        var entities = rawCodes
            .Select(code => new UserMfaRecoveryCode
            {
                TenantId = request.TenantId,
                UserId = request.UserId,
                CodeHash = recoveryCodeService.HashCode(request.TenantId, request.UserId, code),
                CreatedAt = utcNow
            })
            .ToArray();

        user.RecoveryCodesGeneratedAt = utcNow;
        user.UpdatedAt = utcNow;

        await recoveryCodeRepository.ReplaceActiveAsync(request.TenantId, request.UserId, entities, utcNow, cancellationToken);
        await auditTrail.WriteAsync(new AuthAuditRecord(request.TenantId, "auth.mfa.recovery-codes.regenerated", "success", request.UserId, null, user.Email, request.IpAddress, request.UserAgent, request.CorrelationId, request.TraceId), cancellationToken);
        await unitOfWork.SaveChangesAsync(cancellationToken);
        return new RecoveryCodesResult(rawCodes);
    }

    private static AuthApplicationException NotFound() =>
        new("User not found", "User could not be found.", (int)HttpStatusCode.NotFound, errorCode: "user_not_found");
}

public sealed class ListTrustedDevicesQueryHandler(ITrustedDeviceRepository trustedDevices)
    : IRequestHandler<ListTrustedDevicesQuery, TrustedDevicesIdentityResponse>
{
    public async Task<TrustedDevicesIdentityResponse> Handle(ListTrustedDevicesQuery request, CancellationToken cancellationToken)
    {
        var devices = await trustedDevices.ListForUserAsync(request.TenantId, request.UserId, cancellationToken);
        return new TrustedDevicesIdentityResponse(devices.Select(device => new TrustedDeviceIdentityResponse(
            device.Id,
            false,
            device.DeviceName,
            device.IpAddress,
            device.UserAgent,
            device.TrustedAtUtc,
            device.LastSeenAtUtc,
            device.IsRevoked)).ToArray());
    }
}

public sealed class RevokeTrustedDeviceCommandHandler(
    ITrustedDeviceRepository trustedDevices,
    IAuthAuditTrail auditTrail,
    IAuthUnitOfWork unitOfWork,
    IClock clock)
    : IRequestHandler<RevokeTrustedDeviceCommand, bool>
{
    public async Task<bool> Handle(RevokeTrustedDeviceCommand request, CancellationToken cancellationToken)
    {
        var revoked = await trustedDevices.RevokeAsync(request.TenantId, request.UserId, request.DeviceId, clock.UtcDateTime, "user_revoked_trusted_device", cancellationToken);
        if (!revoked)
        {
            return false;
        }

        await auditTrail.WriteAsync(new AuthAuditRecord(request.TenantId, "auth.trusted-device.revoked", "success", request.UserId, null, null, request.IpAddress, request.UserAgent, request.CorrelationId, request.TraceId), cancellationToken);
        await unitOfWork.SaveChangesAsync(cancellationToken);
        return true;
    }
}

public sealed class ConfirmEmailChangeForAccountCommandHandler(
    IUserRepository users,
    IAuthVerificationTokenRepository tokenRepository,
    IAuthVerificationTokenService tokenService,
    IAuthAuditTrail auditTrail,
    IAuthUnitOfWork unitOfWork,
    IUserTokenStateValidator tokenStateValidator,
    IClock clock)
    : IRequestHandler<ConfirmEmailChangeForAccountCommand, EmailChangeConfirmIdentityResult>
{
    public async Task<EmailChangeConfirmIdentityResult> Handle(ConfirmEmailChangeForAccountCommand request, CancellationToken cancellationToken)
    {
        var utcNow = clock.UtcDateTime;
        var user = await users.GetByIdAsync(request.TenantId, request.UserId, cancellationToken) ?? throw InvalidToken();
        var token = await tokenRepository.GetValidAsync(
                request.TenantId,
                request.UserId,
                AuthVerificationTokenPurpose.EmailChange,
                tokenService.HashToken(request.Token),
                utcNow,
                cancellationToken)
            ?? throw InvalidToken();

        if (string.IsNullOrWhiteSpace(token.Target))
        {
            throw InvalidToken();
        }

        if (await users.ExistsByEmailAsync(request.TenantId, token.Target, cancellationToken))
        {
            return new EmailChangeConfirmIdentityResult(false, null, [new PasswordPolicyFailure("email_unavailable", "The supplied email cannot be used.")]);
        }

        token.Consume(utcNow, request.IpAddress);
        user.Email = token.Target;
        user.NormalizedEmail = token.Target;
        user.EmailConfirmed = true;
        user.EmailConfirmedAt = utcNow;
        user.SecurityStamp = Guid.NewGuid().ToString("N");
        user.TokenVersion++;
        user.UpdatedAt = utcNow;

        await auditTrail.WriteAsync(new AuthAuditRecord(request.TenantId, "auth.email-change.confirmed", "success", request.UserId, null, user.Email, request.IpAddress, request.UserAgent, request.CorrelationId, request.TraceId), cancellationToken);
        await unitOfWork.SaveChangesAsync(cancellationToken);
        tokenStateValidator.Evict(request.TenantId, request.UserId);

        return new EmailChangeConfirmIdentityResult(true, user.Email, []);
    }

    private static AuthApplicationException InvalidToken() =>
        new("Invalid token", "The supplied email change token is invalid or expired.", (int)HttpStatusCode.BadRequest, errorCode: "invalid_email_change_token");
}
