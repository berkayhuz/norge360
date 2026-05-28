// <copyright file="LoginCommandHandler.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using System.Net;
using MediatR;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Identity;
using Microsoft.Extensions.Options;
using Norge360.AspNetCore.RequestContext;
using Norge360.Auth.Application.Abstractions;
using Norge360.Auth.Application.Diagnostics;
using Norge360.Auth.Application.Exceptions;
using Norge360.Auth.Application.Features.Commands;
using Norge360.Auth.Application.Helpers;
using Norge360.Auth.Application.Options;
using Norge360.Auth.Application.Records;
using Norge360.Auth.Contracts.Responses;
using Norge360.Auth.Domain.Entities;
using Norge360.Clock;

namespace Norge360.Auth.Application.Features.Handlers;

public sealed class LoginCommandHandler(
    ITenantRepository tenantRepository,
    IUserRepository userRepository,
    IUserSessionRepository userSessionRepository,
    IAuthUnitOfWork unitOfWork,
    IAuthAuditTrail auditTrail,
    IPasswordHasher<User> passwordHasher,
    IAccessTokenFactory accessTokenFactory,
    IRefreshTokenService refreshTokenService,
    IClock clock,
    IOptions<IdentitySecurityOptions> securityOptions,
    IOptions<AccountLifecycleOptions> lifecycleOptions,
    IOptions<AuthorizationOptions> authorizationOptions,
    IAuthSessionService authSessionService,
    ISecurityAlertPublisher securityAlertPublisher,
    IUserTokenStateValidator userTokenStateValidator,
    IUserSessionStateValidator userSessionStateValidator,
    IAuthenticatorTotpService totpService,
    IAuthenticatorKeyProtector authenticatorKeyProtector,
    IRecoveryCodeService recoveryCodeService,
    IUserMfaRecoveryCodeRepository recoveryCodeRepository,
    IHttpContextAccessor httpContextAccessor)
    : IRequestHandler<LoginCommand, AuthenticationTokenResponse>
{
    private const string DummyPassword = "Norge360-Dummy-Password-For-Timing-Only!2026";

    private static readonly Lazy<(User User, string PasswordHash)> DummyPasswordEnvelope = new(() =>
    {
        var user = new User
        {
            TenantId = Guid.Empty,
            UserName = "timing-equalizer",
            NormalizedUserName = "TIMING-EQUALIZER",
            Email = "timing-equalizer@example.invalid",
            NormalizedEmail = "TIMING-EQUALIZER@EXAMPLE.INVALID",
            PasswordHash = string.Empty
        };

        return (user, new PasswordHasher<User>().HashPassword(user, DummyPassword));
    });

    public async Task<AuthenticationTokenResponse> Handle(LoginCommand request, CancellationToken cancellationToken)
    {
        var httpContext = httpContextAccessor.HttpContext;
        var correlationId = httpContext?.Items[RequestContextSupport.CorrelationIdHeaderName]?.ToString();
        var traceId = httpContext?.TraceIdentifier;
        var lockoutEnabled =
            securityOptions.Value.MaxFailedAccessAttempts > 0 &&
            securityOptions.Value.LockoutMinutes > 0;

        var normalizedIdentity = AuthenticationNormalization.Normalize(request.EmailOrUserName);
        var effectiveTenantId = request.TenantId;
        User? user = null;

        if (effectiveTenantId == Guid.Empty)
        {
            var resolvedScope = await userRepository.ResolveLoginScopeByIdentityAsync(normalizedIdentity, cancellationToken);
            if (resolvedScope is null)
            {
                VerifyDummyPassword(request.Password);
                AuthMetrics.AuthFailed.Add(1, new KeyValuePair<string, object?>("reason", "invalid_credentials"));
                throw InvalidCredentials();
            }

            effectiveTenantId = resolvedScope.TenantId;
            user = await userRepository.GetActiveByIdAsync(effectiveTenantId, resolvedScope.UserId, cancellationToken);
            if (user is null)
            {
                VerifyDummyPassword(request.Password);
                AuthMetrics.AuthFailed.Add(1, new KeyValuePair<string, object?>("reason", "invalid_credentials"));
                throw InvalidCredentials();
            }
        }

        var tenant = await tenantRepository.GetByIdAsync(effectiveTenantId, cancellationToken);
        if (tenant is null)
        {
            VerifyDummyPassword(request.Password);
            AuthMetrics.AuthFailed.Add(1, new KeyValuePair<string, object?>("reason", "invalid_credentials"));
            throw InvalidCredentials();
        }

        if (!tenant.IsActive)
        {
            VerifyDummyPassword(request.Password);
            AuthMetrics.AuthFailed.Add(1, new KeyValuePair<string, object?>("reason", "inactive_tenant"));
            throw InvalidCredentials();
        }

        user ??= await userRepository.FindByTenantAndIdentityAsync(
            effectiveTenantId,
            normalizedIdentity,
            cancellationToken);

        if (user is null)
        {
            VerifyDummyPassword(request.Password);
            AuthMetrics.AuthFailed.Add(1, new KeyValuePair<string, object?>("reason", "invalid_credentials"));
            throw InvalidCredentials();
        }

        var utcNow = clock.UtcDateTime;

        if (!user.IsActive || user.IsDeleted)
        {
            VerifyDummyPassword(request.Password);
            AuthMetrics.AuthFailed.Add(1, new KeyValuePair<string, object?>("reason", "inactive_user"));
            throw InvalidCredentials();
        }

        var membership = await userRepository.GetMembershipAsync(effectiveTenantId, user.Id, cancellationToken);
        if (membership is null || !membership.IsActive || membership.IsDeleted)
        {
            VerifyDummyPassword(request.Password);
            AuthMetrics.AuthFailed.Add(1, new KeyValuePair<string, object?>("reason", "inactive_membership"));
            throw InvalidCredentials();
        }

        if (lifecycleOptions.Value.RequireConfirmedEmailForLogin && !user.EmailConfirmed)
        {
            AuthMetrics.AuthFailed.Add(1, new KeyValuePair<string, object?>("reason", "email_unconfirmed"));
            await auditTrail.WriteAsync(
                new AuthAuditRecord(
                    effectiveTenantId,
                    "auth.login.failed",
                    "email_unconfirmed",
                    user.Id,
                    null,
                    request.EmailOrUserName,
                    AuthenticationNormalization.CleanOrNull(request.IpAddress),
                    AuthenticationNormalization.CleanOrNull(request.UserAgent),
                    correlationId,
                    traceId),
                cancellationToken);
            await unitOfWork.SaveChangesAsync(cancellationToken);
            throw new AuthApplicationException("Email confirmation required", "Confirm your email address before signing in.", (int)HttpStatusCode.Forbidden, errorCode: "email_confirmation_required");
        }

        if (lockoutEnabled && user.IsLocked && user.LockoutEndAt.HasValue && user.LockoutEndAt > utcNow)
        {
            AuthMetrics.AuthFailed.Add(1, new KeyValuePair<string, object?>("reason", "locked"));
            await securityAlertPublisher.PublishAsync(
                new SecurityAlert(
                    "auth.lockout",
                    "warning",
                    "Locked account attempted to authenticate.",
                    effectiveTenantId,
                    user.Id,
                    null,
                    correlationId,
                    traceId),
                cancellationToken);
            throw new AuthApplicationException("Account locked", "Too many failed attempts. Try again later.", (int)HttpStatusCode.Forbidden, errorCode: "account_locked");
        }

        var verificationResult = passwordHasher.VerifyHashedPassword(user, user.PasswordHash, request.Password);
        if (verificationResult == PasswordVerificationResult.Failed)
        {
            var lockedAfterFailure = lockoutEnabled &&
                                     user.AccessFailedCount + 1 >= securityOptions.Value.MaxFailedAccessAttempts;
            if (lockoutEnabled)
            {
                await userRepository.RecordFailedLoginAsync(
                    effectiveTenantId,
                    user.Id,
                    securityOptions.Value.MaxFailedAccessAttempts,
                    utcNow.AddMinutes(securityOptions.Value.LockoutMinutes),
                    utcNow,
                    cancellationToken);
            }

            AuthMetrics.AuthFailed.Add(1, new KeyValuePair<string, object?>("reason", lockedAfterFailure ? "locked_after_failure" : "invalid_credentials"));
            await auditTrail.WriteAsync(
                new AuthAuditRecord(
                    effectiveTenantId,
                    "auth.login.failed",
                    lockedAfterFailure ? "locked" : "rejected",
                    user.Id,
                    null,
                    request.EmailOrUserName,
                    AuthenticationNormalization.CleanOrNull(request.IpAddress),
                    AuthenticationNormalization.CleanOrNull(request.UserAgent),
                    correlationId,
                    traceId),
                cancellationToken);

            await securityAlertPublisher.PublishAsync(
                new SecurityAlert(
                    "auth.login.failed",
                    lockedAfterFailure ? "warning" : "info",
                    lockedAfterFailure
                        ? "Login failure locked the account."
                        : "Login failure rejected credentials.",
                    effectiveTenantId,
                    user.Id,
                    null,
                    correlationId,
                    traceId,
                    $"lockedAfterFailure={lockedAfterFailure}"),
                cancellationToken);

            await unitOfWork.SaveChangesAsync(cancellationToken);
            throw InvalidCredentials();
        }

        if (verificationResult == PasswordVerificationResult.SuccessRehashNeeded)
        {
            user.PasswordHash = passwordHasher.HashPassword(user, request.Password);
        }

        if (user.MfaEnabled)
        {
            await EnsureMfaSatisfiedAsync(user, request, effectiveTenantId, utcNow, cancellationToken);
        }

        user.AccessFailedCount = 0;
        user.IsLocked = false;
        user.LockoutEndAt = null;
        user.LastLoginAt = utcNow;
        user.UpdatedAt = utcNow;
        var bootstrapSecurityStateChanged = await EnsureTenantBootstrapOwnerAsync(user, membership, utcNow, cancellationToken);

        var refreshToken = refreshTokenService.Generate(request.RememberMe);
        var session = new UserSession
        {
            TenantId = effectiveTenantId,
            UserId = user.Id,
            IsPersistent = request.RememberMe,
            RefreshTokenFamilyId = Guid.NewGuid(),
            RefreshTokenHash = refreshToken.Hash,
            RefreshTokenExpiresAt = refreshToken.ExpiresAtUtc,
            CreatedAt = utcNow,
            LastSeenAt = utcNow,
            LastRefreshedAt = utcNow,
            IpAddress = AuthenticationNormalization.CleanOrNull(request.IpAddress),
            UserAgent = AuthenticationNormalization.CleanOrNull(request.UserAgent),
            CreatedBy = user.Id.ToString("N")
        };

        await userSessionRepository.AddAsync(session, cancellationToken);
        var revokedSessionIds = await authSessionService.EnforceSessionLimitsAsync(effectiveTenantId, user.Id, session.Id, cancellationToken);
        await auditTrail.WriteAsync(
            new AuthAuditRecord(
                effectiveTenantId,
                "auth.login.succeeded",
                "success",
                user.Id,
                session.Id,
                user.Email,
                session.IpAddress,
                session.UserAgent,
                correlationId,
                traceId),
            cancellationToken);
        await unitOfWork.SaveChangesAsync(cancellationToken);

        if (bootstrapSecurityStateChanged)
        {
            userTokenStateValidator.Evict(effectiveTenantId, user.Id);
        }

        foreach (var sessionId in revokedSessionIds)
        {
            userSessionStateValidator.Evict(effectiveTenantId, sessionId);
        }

        AuthMetrics.AuthSucceeded.Add(1, new KeyValuePair<string, object?>("flow", "login"));

        var accessToken = accessTokenFactory.Create(
            user.Id,
            user.UserName,
            user.Email ?? string.Empty,
            user.TokenVersion,
            membership.GetRoles(),
            membership.GetPermissions(),
            tenant.Id,
            session.Id,
            new DateTimeOffset(utcNow, TimeSpan.Zero),
            ResolveAuthenticationMethods(user, request));
        return new AuthenticationTokenResponse(
            accessToken.Token,
            accessToken.ExpiresAtUtc,
            refreshToken.Token,
            refreshToken.ExpiresAtUtc,
            tenant.Id,
            user.Id,
            user.UserName,
            user.Email ?? string.Empty,
            session.Id,
            request.RememberMe);
    }

    private static AuthApplicationException InvalidCredentials() =>
        new("Invalid credentials", "Username/email or password is invalid.", (int)HttpStatusCode.Unauthorized, errorCode: "invalid_credentials");

    private void VerifyDummyPassword(string suppliedPassword)
    {
        var dummy = DummyPasswordEnvelope.Value;
        passwordHasher.VerifyHashedPassword(dummy.User, dummy.PasswordHash, suppliedPassword);
    }

    private async Task<bool> EnsureTenantBootstrapOwnerAsync(User user, UserTenantMembership membership, DateTime utcNow, CancellationToken cancellationToken)
    {
        var authorization = authorizationOptions.Value;
        if (!authorization.BootstrapFirstUserAsTenantOwner)
        {
            return false;
        }

        if (!await userRepository.IsFirstActiveUserInTenantAsync(membership.TenantId, user.Id, cancellationToken))
        {
            return false;
        }

        var mergedRoles = Merge(membership.GetRoles(), authorization.BootstrapFirstUserRoles);
        var mergedPermissions = Merge(membership.GetPermissions(), authorization.BootstrapFirstUserPermissions);
        var rolesChanged = !SetEquals(membership.GetRoles(), mergedRoles);
        var permissionsChanged = !SetEquals(membership.GetPermissions(), mergedPermissions);
        if (!rolesChanged && !permissionsChanged)
        {
            return false;
        }

        membership.Roles = string.Join(',', mergedRoles);
        membership.Permissions = string.Join(',', mergedPermissions);
        membership.LastRoleChangeAt = utcNow;
        membership.LastRoleChangedByUserId = user.Id;
        membership.UpdatedAt = utcNow;
        membership.UpdatedBy = user.Id.ToString("N");
        user.TokenVersion++;
        user.SecurityStamp = Guid.NewGuid().ToString("N");
        user.UpdatedAt = utcNow;
        return true;
    }

    private static IReadOnlyCollection<string> Merge(IEnumerable<string> current, IEnumerable<string> bootstrap) =>
        current
            .Concat(bootstrap)
            .Where(value => !string.IsNullOrWhiteSpace(value))
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToArray();

    private static bool SetEquals(IEnumerable<string> first, IEnumerable<string> second) =>
        first.ToHashSet(StringComparer.OrdinalIgnoreCase).SetEquals(second);

    private async Task EnsureMfaSatisfiedAsync(User user, LoginCommand request, Guid effectiveTenantId, DateTime utcNow, CancellationToken cancellationToken)
    {
        if (!string.IsNullOrWhiteSpace(request.MfaCode))
        {
            if (string.IsNullOrWhiteSpace(user.AuthenticatorKeyProtected))
            {
                throw MfaRequired();
            }

            var sharedKey = authenticatorKeyProtector.Unprotect(user.AuthenticatorKeyProtected);
            if (!totpService.VerifyCode(sharedKey, request.MfaCode, utcNow))
            {
                throw new AuthApplicationException(
                    "Invalid MFA code",
                    "The supplied authenticator code is invalid.",
                    (int)HttpStatusCode.Unauthorized,
                    errorCode: "invalid_mfa_code");
            }

            return;
        }

        if (!string.IsNullOrWhiteSpace(request.RecoveryCode))
        {
            var codeHash = recoveryCodeService.HashCode(effectiveTenantId, user.Id, request.RecoveryCode);
            var consumed = await recoveryCodeRepository.ConsumeAsync(effectiveTenantId, user.Id, codeHash, utcNow, cancellationToken);
            if (!consumed)
            {
                throw new AuthApplicationException(
                    "Invalid recovery code",
                    "The supplied recovery code is invalid.",
                    (int)HttpStatusCode.Unauthorized,
                    errorCode: "invalid_recovery_code");
            }

            return;
        }

        throw MfaRequired();
    }

    private static AuthApplicationException MfaRequired() =>
        new(
            "Second factor required",
            "Multi-factor authentication challenge is required for this account.",
            (int)HttpStatusCode.Unauthorized,
            errorCode: "mfa_required");

    private static IReadOnlyCollection<string> ResolveAuthenticationMethods(User user, LoginCommand request)
    {
        if (user.MfaEnabled && (!string.IsNullOrWhiteSpace(request.MfaCode) || !string.IsNullOrWhiteSpace(request.RecoveryCode)))
        {
            return ["pwd", "mfa"];
        }

        return ["pwd"];
    }
}
