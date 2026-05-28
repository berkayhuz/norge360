// <copyright file="InvitationCommandHandlers.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using System.Net;
using MediatR;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using Norge360.Auth.Application.Abstractions;
using Norge360.Auth.Application.Descriptors;
using Norge360.Auth.Application.Diagnostics;
using Norge360.Auth.Application.Exceptions;
using Norge360.Auth.Application.Features.Commands;
using Norge360.Auth.Application.Helpers;
using Norge360.Auth.Application.Options;
using Norge360.Auth.Application.Records;
using Norge360.Auth.Contracts.IntegrationEvents;
using Norge360.Auth.Contracts.Responses;
using Norge360.Auth.Domain.Entities;
using Norge360.Clock;

namespace Norge360.Auth.Application.Features.Handlers;

public sealed class CreateTenantInvitationCommandHandler(
    ITenantRepository tenants,
    IUserRepository users,
    ITenantInvitationRepository invitations,
    IAuthVerificationTokenService tokenService,
    IInviteNotificationDispatcher inviteNotifications,
    IAuthAuditTrail auditTrail,
    IAuthUnitOfWork unitOfWork,
    IClock clock,
    IOptions<AccountLifecycleOptions> lifecycleOptions,
    IOptions<AuthorizationOptions> authorizationOptions,
    IOptions<InvitationDeliveryOptions> invitationDeliveryOptions)
    : IRequestHandler<CreateTenantInvitationCommand, TenantInvitationResponse>
{
    public async Task<TenantInvitationResponse> Handle(CreateTenantInvitationCommand request, CancellationToken cancellationToken)
    {
        var tenant = await tenants.GetByIdAsync(request.TenantId, cancellationToken)
            ?? throw new AuthApplicationException("Tenant not found", "Tenant could not be resolved.", (int)HttpStatusCode.NotFound, errorCode: "tenant_not_found");

        var inviter = await GetAuthorizedInviteManagerAsync(request.TenantId, request.InvitedByUserId, cancellationToken);

        var utcNow = clock.UtcDateTime;
        var normalizedEmail = AuthenticationNormalization.Normalize(request.Email);
        var invitedUser = await users.FindByTenantAndIdentityAsync(request.TenantId, normalizedEmail, cancellationToken);
        if (await users.ExistsByEmailAsync(request.TenantId, normalizedEmail, cancellationToken))
        {
            throw new AuthApplicationException("Invitation conflict", "A user with this email already exists in the tenant.", (int)HttpStatusCode.Conflict, errorCode: "invite_identity_conflict");
        }

        if (await invitations.HasPendingInviteForEmailAsync(request.TenantId, normalizedEmail, utcNow, cancellationToken))
        {
            throw new AuthApplicationException("Invitation conflict", "A pending invitation already exists for this email.", (int)HttpStatusCode.Conflict, errorCode: "invite_pending_conflict");
        }

        var token = tokenService.GenerateToken();
        var authorization = authorizationOptions.Value;
        var invitation = new TenantInvitation
        {
            TenantId = tenant.Id,
            InvitedByUserId = inviter.Id,
            Email = request.Email.Trim(),
            NormalizedEmail = normalizedEmail,
            FirstName = AuthenticationNormalization.CleanOrNull(request.FirstName),
            LastName = AuthenticationNormalization.CleanOrNull(request.LastName),
            TokenHash = tokenService.HashToken(token),
            ExpiresAtUtc = utcNow.AddMinutes(lifecycleOptions.Value.InvitationTokenMinutes),
            CreatedAt = utcNow,
            CreatedBy = inviter.Id.ToString("N"),
            Roles = JoinDistinct(authorization.DefaultRoles),
            Permissions = JoinDistinct(authorization.DefaultPermissions)
        };
        await invitations.AddAsync(invitation, cancellationToken);
        await auditTrail.WriteAsync(
            new AuthAuditRecord(
                tenant.Id,
                "auth.invitation.created",
                "success",
                inviter.Id,
                null,
                invitation.Email,
                AuthenticationNormalization.CleanOrNull(request.IpAddress),
                AuthenticationNormalization.CleanOrNull(request.UserAgent),
                request.CorrelationId,
                request.TraceId),
            cancellationToken);

        await unitOfWork.SaveChangesAsync(cancellationToken);
        await SendCreatedInviteAsync(tenant, invitation, inviter, invitedUser, token, request, utcNow, cancellationToken);

        return ToResponse(invitation, utcNow);
    }

    private static string JoinDistinct(IEnumerable<string> values) =>
        string.Join(',', values.Where(value => !string.IsNullOrWhiteSpace(value)).Distinct(StringComparer.OrdinalIgnoreCase));

    private async Task<User> GetAuthorizedInviteManagerAsync(Guid tenantId, Guid userId, CancellationToken cancellationToken)
    {
        var inviter = await users.GetActiveByIdAsync(tenantId, userId, cancellationToken)
            ?? throw new AuthApplicationException("Forbidden", "Invitation can only be managed by a tenant user.", (int)HttpStatusCode.Forbidden, errorCode: "invite_forbidden");
        var membership = await users.GetMembershipAsync(tenantId, userId, cancellationToken)
            ?? throw new AuthApplicationException("Forbidden", "Invitation can only be managed by a tenant user.", (int)HttpStatusCode.Forbidden, errorCode: "invite_forbidden");

        if (!membership.GetPermissions().Contains("*", StringComparer.OrdinalIgnoreCase) &&
            !membership.GetPermissions().Contains("tenant.users.invite", StringComparer.OrdinalIgnoreCase))
        {
            throw new AuthApplicationException("Forbidden", "User invitation requires tenant user management permission.", (int)HttpStatusCode.Forbidden, errorCode: "invite_forbidden");
        }

        return inviter;
    }

    internal static TenantInvitationResponse ToResponse(TenantInvitation invitation, DateTime utcNow) =>
        new(invitation.TenantId, invitation.Id, invitation.Email, invitation.ExpiresAtUtc, invitation.GetStatus(utcNow), invitation.LastSentAtUtc);

    internal static TenantInvitationSummaryResponse ToSummary(TenantInvitation invitation, DateTime utcNow) =>
        new(
            invitation.TenantId,
            invitation.Id,
            invitation.Email,
            invitation.FirstName,
            invitation.LastName,
            invitation.ExpiresAtUtc,
            invitation.GetStatus(utcNow),
            invitation.ResendCount,
            invitation.CreatedAt,
            invitation.LastSentAtUtc,
            invitation.AcceptedAtUtc,
            invitation.RevokedAtUtc,
            invitation.LastDeliveryStatus);

    internal static void MarkDeliveryAttempt(TenantInvitation invitation, DateTime utcNow, string? correlationId, string status, string? errorCode)
    {
        invitation.LastSentAtUtc = utcNow;
        invitation.LastDeliveryAttemptAtUtc = utcNow;
        invitation.LastDeliveryStatus = status;
        invitation.LastDeliveryErrorCode = errorCode;
        invitation.LastDeliveryCorrelationId = AuthenticationNormalization.CleanOrNull(correlationId);
    }

    private async Task SendCreatedInviteAsync(
        Tenant tenant,
        TenantInvitation invitation,
        User inviter,
        User? invitedUser,
        string token,
        CreateTenantInvitationCommand request,
        DateTime utcNow,
        CancellationToken cancellationToken)
    {
        var deliveryOptions = invitationDeliveryOptions.Value;
        if (deliveryOptions.DisableDelivery)
        {
            MarkDeliveryAttempt(invitation, utcNow, request.CorrelationId, "disabled", null);
            await auditTrail.WriteAsync(new AuthAuditRecord(tenant.Id, "auth.invitation.delivery.skipped", "disabled", inviter.Id, null, invitation.Email, AuthenticationNormalization.CleanOrNull(request.IpAddress), AuthenticationNormalization.CleanOrNull(request.UserAgent), request.CorrelationId, request.TraceId), cancellationToken);
            await unitOfWork.SaveChangesAsync(cancellationToken);
            return;
        }

        try
        {
            await inviteNotifications.SendInviteCreatedAsync(tenant, invitation, inviter, invitedUser, token, request.CorrelationId, request.TraceId, utcNow, cancellationToken);
            MarkDeliveryAttempt(invitation, utcNow, request.CorrelationId, "sent", null);
            await auditTrail.WriteAsync(new AuthAuditRecord(tenant.Id, "auth.invitation.delivery.attempted", "sent", inviter.Id, null, invitation.Email, AuthenticationNormalization.CleanOrNull(request.IpAddress), AuthenticationNormalization.CleanOrNull(request.UserAgent), request.CorrelationId, request.TraceId), cancellationToken);
        }
        catch (Exception)
        {
            MarkDeliveryAttempt(invitation, utcNow, request.CorrelationId, "failed", "delivery_failed");
            await auditTrail.WriteAsync(new AuthAuditRecord(tenant.Id, "auth.invitation.delivery.failed", "delivery_failed", inviter.Id, null, invitation.Email, AuthenticationNormalization.CleanOrNull(request.IpAddress), AuthenticationNormalization.CleanOrNull(request.UserAgent), request.CorrelationId, request.TraceId), cancellationToken);
        }

        await unitOfWork.SaveChangesAsync(cancellationToken);
    }
}

public sealed class ListTenantInvitationsCommandHandler(
    IUserRepository users,
    ITenantInvitationRepository invitations,
    IClock clock)
    : IRequestHandler<ListTenantInvitationsCommand, IReadOnlyCollection<TenantInvitationSummaryResponse>>
{
    public async Task<IReadOnlyCollection<TenantInvitationSummaryResponse>> Handle(ListTenantInvitationsCommand request, CancellationToken cancellationToken)
    {
        await EnsureCanManageInvitesAsync(users, request.TenantId, request.RequestedByUserId, cancellationToken);
        var utcNow = clock.UtcDateTime;
        var items = await invitations.ListForTenantAsync(request.TenantId, cancellationToken);
        return items.Select(invitation => CreateTenantInvitationCommandHandler.ToSummary(invitation, utcNow)).ToArray();
    }

    internal static async Task<User> EnsureCanManageInvitesAsync(IUserRepository users, Guid tenantId, Guid userId, CancellationToken cancellationToken)
    {
        var user = await users.GetActiveByIdAsync(tenantId, userId, cancellationToken)
            ?? throw new AuthApplicationException("Forbidden", "Invitation can only be managed by a tenant user.", (int)HttpStatusCode.Forbidden, errorCode: "invite_forbidden");
        var membership = await users.GetMembershipAsync(tenantId, userId, cancellationToken)
            ?? throw new AuthApplicationException("Forbidden", "Invitation can only be managed by a tenant user.", (int)HttpStatusCode.Forbidden, errorCode: "invite_forbidden");

        if (!membership.GetPermissions().Contains("*", StringComparer.OrdinalIgnoreCase) &&
            !membership.GetPermissions().Contains("tenant.users.invite", StringComparer.OrdinalIgnoreCase))
        {
            throw new AuthApplicationException("Forbidden", "User invitation requires tenant user management permission.", (int)HttpStatusCode.Forbidden, errorCode: "invite_forbidden");
        }

        return user;
    }
}

public sealed class ResendTenantInvitationCommandHandler(
    ITenantRepository tenants,
    IUserRepository users,
    ITenantInvitationRepository invitations,
    IAuthVerificationTokenService tokenService,
    IInviteNotificationDispatcher inviteNotifications,
    IAuthAuditTrail auditTrail,
    IAuthUnitOfWork unitOfWork,
    IClock clock,
    IOptions<AccountLifecycleOptions> lifecycleOptions,
    IOptions<InvitationDeliveryOptions> invitationDeliveryOptions)
    : IRequestHandler<ResendTenantInvitationCommand, TenantInvitationResponse>
{
    public async Task<TenantInvitationResponse> Handle(ResendTenantInvitationCommand request, CancellationToken cancellationToken)
    {
        var tenant = await tenants.GetByIdAsync(request.TenantId, cancellationToken)
            ?? throw new AuthApplicationException("Tenant not found", "Tenant could not be resolved.", (int)HttpStatusCode.NotFound, errorCode: "tenant_not_found");
        var inviter = await ListTenantInvitationsCommandHandler.EnsureCanManageInvitesAsync(users, request.TenantId, request.RequestedByUserId, cancellationToken);
        var invitation = await invitations.GetByIdAsync(request.TenantId, request.InvitationId, cancellationToken)
            ?? throw new AuthApplicationException("Invitation not found", "Invitation could not be found.", (int)HttpStatusCode.NotFound, errorCode: "invitation_not_found");

        var utcNow = clock.UtcDateTime;
        if (invitation.AcceptedAtUtc is not null)
        {
            throw new AuthApplicationException("Invitation cannot be resent", "Accepted invitations cannot be resent.", (int)HttpStatusCode.Conflict, errorCode: "invitation_already_accepted");
        }

        if (invitation.RevokedAtUtc is not null || !invitation.IsActive)
        {
            throw new AuthApplicationException("Invitation cannot be resent", "Revoked invitations cannot be resent.", (int)HttpStatusCode.Conflict, errorCode: "invitation_revoked");
        }

        var deliveryOptions = invitationDeliveryOptions.Value;
        if (invitation.ResendCount >= deliveryOptions.MaxResends)
        {
            throw new AuthApplicationException("Invitation cannot be resent", "Invitation resend limit has been reached.", (int)HttpStatusCode.TooManyRequests, errorCode: "invitation_resend_limit");
        }

        if (invitation.LastSentAtUtc is not null &&
            invitation.LastSentAtUtc.Value.AddSeconds(deliveryOptions.ResendThrottleSeconds) > utcNow)
        {
            throw new AuthApplicationException("Invitation cannot be resent yet", "Invitation resend throttle is active.", (int)HttpStatusCode.TooManyRequests, errorCode: "invitation_resend_throttled");
        }

        var token = tokenService.GenerateToken();
        invitation.TokenHash = tokenService.HashToken(token);
        invitation.ExpiresAtUtc = utcNow.AddMinutes(lifecycleOptions.Value.InvitationTokenMinutes);
        invitation.ResendCount++;
        invitation.UpdatedAt = utcNow;
        invitation.UpdatedBy = inviter.Id.ToString("N");
        await auditTrail.WriteAsync(new AuthAuditRecord(request.TenantId, "auth.invitation.resent", "accepted", inviter.Id, null, invitation.Email, request.IpAddress, request.UserAgent, request.CorrelationId, request.TraceId), cancellationToken);
        await unitOfWork.SaveChangesAsync(cancellationToken);
        var invitedUser = await users.FindByTenantAndIdentityAsync(request.TenantId, invitation.NormalizedEmail, cancellationToken);
        await SendResentInviteAsync(tenant, invitation, inviter, invitedUser, token, request, utcNow, cancellationToken);

        return CreateTenantInvitationCommandHandler.ToResponse(invitation, utcNow);
    }

    private async Task SendResentInviteAsync(
        Tenant tenant,
        TenantInvitation invitation,
        User inviter,
        User? invitedUser,
        string token,
        ResendTenantInvitationCommand request,
        DateTime utcNow,
        CancellationToken cancellationToken)
    {
        var deliveryOptions = invitationDeliveryOptions.Value;
        if (deliveryOptions.DisableDelivery)
        {
            CreateTenantInvitationCommandHandler.MarkDeliveryAttempt(invitation, utcNow, request.CorrelationId, "disabled", null);
            await auditTrail.WriteAsync(new AuthAuditRecord(request.TenantId, "auth.invitation.delivery.skipped", "disabled", inviter.Id, null, invitation.Email, request.IpAddress, request.UserAgent, request.CorrelationId, request.TraceId), cancellationToken);
            await unitOfWork.SaveChangesAsync(cancellationToken);
            return;
        }

        try
        {
            await inviteNotifications.SendInviteResentAsync(tenant, invitation, inviter, invitedUser, token, request.CorrelationId, request.TraceId, utcNow, cancellationToken);
            CreateTenantInvitationCommandHandler.MarkDeliveryAttempt(invitation, utcNow, request.CorrelationId, "sent", null);
            await auditTrail.WriteAsync(new AuthAuditRecord(request.TenantId, "auth.invitation.delivery.attempted", "sent", inviter.Id, null, invitation.Email, request.IpAddress, request.UserAgent, request.CorrelationId, request.TraceId), cancellationToken);
        }
        catch (Exception)
        {
            CreateTenantInvitationCommandHandler.MarkDeliveryAttempt(invitation, utcNow, request.CorrelationId, "failed", "delivery_failed");
            await auditTrail.WriteAsync(new AuthAuditRecord(request.TenantId, "auth.invitation.delivery.failed", "delivery_failed", inviter.Id, null, invitation.Email, request.IpAddress, request.UserAgent, request.CorrelationId, request.TraceId), cancellationToken);
        }

        await unitOfWork.SaveChangesAsync(cancellationToken);
    }
}

public sealed class RevokeTenantInvitationCommandHandler(
    IUserRepository users,
    ITenantInvitationRepository invitations,
    IAuthAuditTrail auditTrail,
    IAuthUnitOfWork unitOfWork,
    IClock clock)
    : IRequestHandler<RevokeTenantInvitationCommand, TenantInvitationResponse>
{
    public async Task<TenantInvitationResponse> Handle(RevokeTenantInvitationCommand request, CancellationToken cancellationToken)
    {
        var user = await ListTenantInvitationsCommandHandler.EnsureCanManageInvitesAsync(users, request.TenantId, request.RequestedByUserId, cancellationToken);
        var invitation = await invitations.GetByIdAsync(request.TenantId, request.InvitationId, cancellationToken)
            ?? throw new AuthApplicationException("Invitation not found", "Invitation could not be found.", (int)HttpStatusCode.NotFound, errorCode: "invitation_not_found");

        var utcNow = clock.UtcDateTime;
        if (invitation.AcceptedAtUtc is not null)
        {
            throw new AuthApplicationException("Invitation cannot be revoked", "Accepted invitations cannot be revoked.", (int)HttpStatusCode.Conflict, errorCode: "invitation_already_accepted");
        }

        if (invitation.RevokedAtUtc is null)
        {
            invitation.RevokedAtUtc = utcNow;
            invitation.RevokedByUserId = user.Id;
            invitation.Deactivate();
            invitation.UpdatedAt = utcNow;
            invitation.UpdatedBy = user.Id.ToString("N");
            invitation.LastDeliveryStatus = "revoked";
        }

        await auditTrail.WriteAsync(new AuthAuditRecord(request.TenantId, "auth.invitation.revoked", "success", user.Id, null, invitation.Email, request.IpAddress, request.UserAgent, request.CorrelationId, request.TraceId), cancellationToken);
        await unitOfWork.SaveChangesAsync(cancellationToken);

        return CreateTenantInvitationCommandHandler.ToResponse(invitation, utcNow);
    }
}

public sealed class AcceptTenantInvitationCommandHandler(
    ITenantRepository tenants,
    IUserRepository users,
    IUserSessionRepository sessions,
    ITenantInvitationRepository invitations,
    IAuthUnitOfWork unitOfWork,
    IAuthAuditTrail auditTrail,
    IIntegrationEventOutbox integrationEventOutbox,
    IAuthVerificationTokenRepository verificationTokenRepository,
    IAuthVerificationTokenService tokenService,
    IPasswordHasher<User> passwordHasher,
    IAccessTokenFactory accessTokenFactory,
    IRefreshTokenService refreshTokenService,
    IClock clock,
    IOptions<AccountLifecycleOptions> lifecycleOptions,
    IAuthSessionService authSessionService,
    IUserSessionStateValidator userSessionStateValidator)
    : IRequestHandler<AcceptTenantInvitationCommand, AuthSessionResult>
{
    public async Task<AuthSessionResult> Handle(AcceptTenantInvitationCommand request, CancellationToken cancellationToken)
    {
        var utcNow = clock.UtcDateTime;
        var tenant = await tenants.GetByIdAsync(request.TenantId, cancellationToken);
        if (tenant is null)
        {
            await WriteAcceptanceFailedAsync(request, "tenant_not_found", cancellationToken);
            throw InvalidInvitation();
        }

        var invitation = await invitations.GetPendingByTokenHashAsync(
            request.TenantId,
            tokenService.HashToken(request.Token),
            utcNow,
            cancellationToken);
        if (invitation is null)
        {
            await WriteAcceptanceFailedAsync(request, "invalid_or_expired", cancellationToken);
            throw InvalidInvitation();
        }

        var normalizedEmail = AuthenticationNormalization.Normalize(request.Email);
        if (!string.Equals(invitation.NormalizedEmail, normalizedEmail, StringComparison.Ordinal))
        {
            await WriteAcceptanceFailedAsync(request, "email_mismatch", cancellationToken);
            throw InvalidInvitation();
        }

        var normalizedUserName = AuthenticationNormalization.Normalize(request.UserName);
        var existingUser = await users.FindByTenantAndIdentityAsync(request.TenantId, normalizedEmail, cancellationToken);
        var isNewIdentity = existingUser is null;

        if (existingUser is null)
        {
            var identityAlreadyExists =
                await users.ExistsByUserNameAsync(request.TenantId, normalizedUserName, cancellationToken) ||
                await users.ExistsByEmailAsync(request.TenantId, normalizedEmail, cancellationToken);
            if (identityAlreadyExists)
            {
                await WriteAcceptanceFailedAsync(request, "identity_conflict", cancellationToken);
                throw new AuthApplicationException("Registration could not be completed", "The invitation could not be accepted with the supplied identity.", (int)HttpStatusCode.Conflict, errorCode: "invitation_identity_conflict");
            }

            existingUser = new User
            {
                TenantId = tenant.Id,
                UserName = request.UserName.Trim(),
                NormalizedUserName = normalizedUserName,
                Email = request.Email.Trim(),
                NormalizedEmail = normalizedEmail,
                FirstName = AuthenticationNormalization.CleanOrNull(request.FirstName) ?? invitation.FirstName,
                LastName = AuthenticationNormalization.CleanOrNull(request.LastName) ?? invitation.LastName,
                CreatedAt = utcNow,
                CreatedBy = invitation.InvitedByUserId.ToString("N"),
                LastLoginAt = utcNow,
                Roles = invitation.Roles,
                Permissions = invitation.Permissions
            };
            existingUser.PasswordHash = passwordHasher.HashPassword(existingUser, request.Password);
            await users.AddAsync(existingUser, cancellationToken);
        }
        else
        {
            var conflictingMember = await users.FindByTenantAndIdentityAsync(request.TenantId, existingUser.NormalizedUserName, cancellationToken);
            if (conflictingMember is not null && conflictingMember.Id != existingUser.Id)
            {
                await WriteAcceptanceFailedAsync(request, "identity_conflict", cancellationToken);
                throw new AuthApplicationException("Registration could not be completed", "The invitation could not be accepted with the supplied identity.", (int)HttpStatusCode.Conflict, errorCode: "invitation_identity_conflict");
            }

            var passwordVerificationResult = passwordHasher.VerifyHashedPassword(existingUser, existingUser.PasswordHash, request.Password);
            if (passwordVerificationResult == PasswordVerificationResult.Failed)
            {
                await WriteAcceptanceFailedAsync(request, "existing_identity_verification_failed", cancellationToken);
                throw new AuthApplicationException("Invalid credentials", "The supplied credentials are invalid for this invited account.", (int)HttpStatusCode.Unauthorized, errorCode: "invitation_identity_verification_failed");
            }

            if (passwordVerificationResult == PasswordVerificationResult.SuccessRehashNeeded)
            {
                existingUser.PasswordHash = passwordHasher.HashPassword(existingUser, request.Password);
            }
        }

        var membership = await users.GetMembershipAsync(request.TenantId, existingUser.Id, cancellationToken);
        if (membership is null)
        {
            membership = new UserTenantMembership
            {
                TenantId = tenant.Id,
                UserId = existingUser.Id,
                Roles = invitation.Roles,
                Permissions = invitation.Permissions,
                CreatedAt = utcNow,
                CreatedBy = invitation.InvitedByUserId.ToString("N")
            };
            await users.AddMembershipAsync(membership, cancellationToken);
        }

        existingUser.UpdatedAt = utcNow;

        invitation.AcceptedAtUtc = utcNow;
        invitation.AcceptedByUserId = existingUser.Id;
        invitation.UpdatedAt = utcNow;
        invitation.UpdatedBy = existingUser.Id.ToString("N");

        var lifecycle = lifecycleOptions.Value;
        var shouldIssueAuthenticatedSession = !lifecycle.RequireConfirmedEmailForLogin || existingUser.EmailConfirmed;
        RefreshTokenDescriptor? refreshToken = null;
        UserSession? session = null;
        if (shouldIssueAuthenticatedSession)
        {
            existingUser.LastLoginAt = utcNow;
            refreshToken = refreshTokenService.Generate(isPersistent: true);
            session = new UserSession
            {
                TenantId = tenant.Id,
                UserId = existingUser.Id,
                IsPersistent = true,
                RefreshTokenFamilyId = Guid.NewGuid(),
                RefreshTokenHash = refreshToken.Hash,
                RefreshTokenExpiresAt = refreshToken.ExpiresAtUtc,
                CreatedAt = utcNow,
                LastSeenAt = utcNow,
                LastRefreshedAt = utcNow,
                IpAddress = AuthenticationNormalization.CleanOrNull(request.IpAddress),
                UserAgent = AuthenticationNormalization.CleanOrNull(request.UserAgent),
                CreatedBy = existingUser.Id.ToString("N")
            };
            await sessions.AddAsync(session, cancellationToken);
        }

        if (isNewIdentity)
        {
            var emailConfirmationToken = tokenService.GenerateToken();
            var emailConfirmationExpiresAt = utcNow.AddMinutes(lifecycle.EmailConfirmationTokenMinutes);

            await verificationTokenRepository.AddAsync(
                new AuthVerificationToken
                {
                    TenantId = tenant.Id,
                    UserId = existingUser.Id,
                    Purpose = AuthVerificationTokenPurpose.EmailConfirmation,
                    TokenHash = tokenService.HashToken(emailConfirmationToken),
                    Target = existingUser.Email,
                    ExpiresAtUtc = emailConfirmationExpiresAt,
                    CreatedAt = utcNow
                },
                cancellationToken);

            await integrationEventOutbox.AddAsync(
                Guid.NewGuid(),
                AuthEmailConfirmationRequestedV1.EventName,
                AuthEmailConfirmationRequestedV1.EventVersion,
                AuthEmailConfirmationRequestedV1.RoutingKey,
                "Norge360.Auth",
                new AuthEmailConfirmationRequestedV1(
                    existingUser.Id,
                    tenant.Id,
                    existingUser.UserName,
                    existingUser.Email ?? string.Empty,
                    emailConfirmationToken,
                    AccountLifecycleLinkBuilder.Build(lifecycle.PublicAppBaseUrl, lifecycle.ConfirmEmailPath, tenant.Id, existingUser.Id, emailConfirmationToken, existingUser.Email),
                    emailConfirmationExpiresAt),
                request.CorrelationId,
                request.TraceId,
                utcNow,
                cancellationToken);
        }

        var revokedSessionIds = session is null
            ? []
            : await authSessionService.EnforceSessionLimitsAsync(tenant.Id, existingUser.Id, session.Id, cancellationToken);
        await auditTrail.WriteAsync(
            new AuthAuditRecord(
                tenant.Id,
                "auth.invitation.accepted",
                "success",
                existingUser.Id,
                session?.Id,
                existingUser.Email,
                session?.IpAddress,
                session?.UserAgent,
                request.CorrelationId,
                request.TraceId),
            cancellationToken);

        await integrationEventOutbox.AddAsync(
            Guid.NewGuid(),
            UserRegisteredV1.EventName,
            UserRegisteredV1.EventVersion,
            UserRegisteredV1.RoutingKey,
            "Norge360.Auth",
            new UserRegisteredV1(existingUser.Id, tenant.Id, existingUser.UserName, existingUser.Email ?? string.Empty, existingUser.FirstName, existingUser.LastName, utcNow),
            request.CorrelationId,
            request.TraceId,
            utcNow,
            cancellationToken);

        try
        {
            await unitOfWork.SaveChangesAsync(cancellationToken);
        }
        catch (DbUpdateException)
        {
            throw new AuthApplicationException("Invitation could not be accepted", "The invitation could not be accepted.", (int)HttpStatusCode.Conflict, errorCode: "invitation_accept_conflict");
        }

        foreach (var sessionId in revokedSessionIds)
        {
            userSessionStateValidator.Evict(tenant.Id, sessionId);
        }

        if (session is null || refreshToken is null)
        {
            return new AuthSessionResult.PendingConfirmation(tenant.Id, existingUser.Id, existingUser.Email ?? string.Empty);
        }

        AuthMetrics.AuthSucceeded.Add(1, new KeyValuePair<string, object?>("flow", "invite-accept"));

        var accessToken = accessTokenFactory.Create(
            existingUser.Id,
            existingUser.UserName,
            existingUser.Email ?? string.Empty,
            existingUser.TokenVersion,
            membership.GetRoles(),
            membership.GetPermissions(),
            tenant.Id,
            session.Id);
        return new AuthSessionResult.Issued(
            new AuthenticationTokenResponse(
                accessToken.Token,
                accessToken.ExpiresAtUtc,
                refreshToken.Token,
                refreshToken.ExpiresAtUtc,
                tenant.Id,
                existingUser.Id,
                existingUser.UserName,
                existingUser.Email ?? string.Empty,
                session.Id,
                IsPersistent: true));
    }

    private static AuthApplicationException InvalidInvitation() =>
        new(
            "Invalid invitation",
            "The invitation is invalid, expired, already used, or does not belong to this tenant.",
            (int)HttpStatusCode.BadRequest,
            errorCode: "invalid_invitation");

    private async Task WriteAcceptanceFailedAsync(AcceptTenantInvitationCommand request, string reason, CancellationToken cancellationToken)
    {
        await auditTrail.WriteAsync(
            new AuthAuditRecord(
                request.TenantId,
                "auth.invitation.acceptance_failed",
                reason,
                null,
                null,
                AuthenticationNormalization.CleanOrNull(request.Email),
                AuthenticationNormalization.CleanOrNull(request.IpAddress),
                AuthenticationNormalization.CleanOrNull(request.UserAgent),
                request.CorrelationId,
                request.TraceId),
            cancellationToken);
        await unitOfWork.SaveChangesAsync(cancellationToken);
    }
}
