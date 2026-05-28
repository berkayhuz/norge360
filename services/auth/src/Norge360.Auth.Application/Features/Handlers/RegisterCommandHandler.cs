// <copyright file="RegisterCommandHandler.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using System.Net;
using System.Text.RegularExpressions;
using MediatR;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using Norge360.AspNetCore.RequestContext;
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
using Norge360.Localization;

namespace Norge360.Auth.Application.Features.Handlers;

public sealed partial class RegisterCommandHandler(
    ITenantRepository tenantRepository,
    IUserRepository userRepository,
    IUserSessionRepository userSessionRepository,
    IAuthUnitOfWork unitOfWork,
    IAuthAuditTrail auditTrail,
    IIntegrationEventOutbox integrationEventOutbox,
    IAuthVerificationTokenRepository verificationTokenRepository,
    IAuthVerificationTokenService verificationTokenService,
    IPasswordHasher<User> passwordHasher,
    IAccessTokenFactory accessTokenFactory,
    IRefreshTokenService refreshTokenService,
    IClock clock,
    IOptions<AuthorizationOptions> authorizationOptions,
    IOptions<AccountLifecycleOptions> lifecycleOptions,
    IAuthSessionService authSessionService,
    IUserSessionStateValidator userSessionStateValidator,
    IHttpContextAccessor httpContextAccessor)
    : IRequestHandler<RegisterCommand, AuthSessionResult>
{
    public async Task<AuthSessionResult> Handle(RegisterCommand request, CancellationToken cancellationToken)
    {
        var httpContext = httpContextAccessor.HttpContext;
        var correlationId = httpContext?.Items[RequestContextSupport.CorrelationIdHeaderName]?.ToString();
        var traceId = httpContext?.TraceIdentifier;
        var utcNow = clock.UtcDateTime;
        var culture = Norge360Cultures.NormalizeOrDefault(request.Culture);
        var lifecycle = lifecycleOptions.Value;
        var shouldIssueAuthenticatedSession = !lifecycle.RequireConfirmedEmailForLogin;
        var normalizedEmail = AuthenticationNormalization.Normalize(request.Email);

        if (await userRepository.ExistsByEmailAsync(normalizedEmail, cancellationToken))
        {
            throw DuplicateEmailConflict();
        }

        var tenant = new Tenant
        {
            Id = Guid.NewGuid(),
            Name = request.TenantName.Trim(),
            Slug = CreateUniqueSlug(request.TenantName),
            IsActive = true,
            CreatedAt = utcNow
        };

        var authorization = authorizationOptions.Value;
        var roles = authorization.BootstrapFirstUserAsTenantOwner
            ? authorization.BootstrapFirstUserRoles
            : authorization.DefaultRoles;
        var permissions = authorization.BootstrapFirstUserAsTenantOwner
            ? authorization.BootstrapFirstUserPermissions
            : authorization.DefaultPermissions;

        var user = new User
        {
            TenantId = tenant.Id,
            UserName = request.UserName.Trim(),
            NormalizedUserName = AuthenticationNormalization.Normalize(request.UserName),
            Email = request.Email.Trim(),
            NormalizedEmail = normalizedEmail,
            FirstName = AuthenticationNormalization.CleanOrNull(request.FirstName),
            LastName = AuthenticationNormalization.CleanOrNull(request.LastName),
            CreatedAt = utcNow,
            CreatedBy = "public-register",
            Roles = JoinDistinct(roles),
            Permissions = JoinDistinct(permissions)
        };
        var tenantMembership = new UserTenantMembership
        {
            TenantId = tenant.Id,
            UserId = user.Id,
            Roles = user.Roles,
            Permissions = user.Permissions,
            CreatedAt = utcNow,
            CreatedBy = "public-register"
        };

        tenant.CreatedBy = user.Id.ToString("N");
        user.PasswordHash = passwordHasher.HashPassword(user, request.Password);

        var emailConfirmationToken = verificationTokenService.GenerateToken();
        var emailConfirmationExpiresAt = utcNow.AddMinutes(lifecycle.EmailConfirmationTokenMinutes);
        RefreshTokenDescriptor? refreshToken = null;
        UserSession? session = null;
        if (shouldIssueAuthenticatedSession)
        {
            user.LastLoginAt = utcNow;
            refreshToken = refreshTokenService.Generate(isPersistent: true);
            session = new UserSession
            {
                TenantId = tenant.Id,
                UserId = user.Id,
                IsPersistent = true,
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
        }

        await tenantRepository.AddAsync(tenant, cancellationToken);
        await userRepository.AddAsync(user, cancellationToken);
        await userRepository.AddMembershipAsync(tenantMembership, cancellationToken);
        if (session is not null)
        {
            await userSessionRepository.AddAsync(session, cancellationToken);
        }

        await verificationTokenRepository.AddAsync(
            new AuthVerificationToken
            {
                TenantId = tenant.Id,
                UserId = user.Id,
                Purpose = AuthVerificationTokenPurpose.EmailConfirmation,
                TokenHash = verificationTokenService.HashToken(emailConfirmationToken),
                Target = user.Email,
                ExpiresAtUtc = emailConfirmationExpiresAt,
                CreatedAt = utcNow
            },
            cancellationToken);

        var revokedSessionIds = session is null
            ? []
            : await authSessionService.EnforceSessionLimitsAsync(tenant.Id, user.Id, session.Id, cancellationToken);
        await auditTrail.WriteAsync(
            new AuthAuditRecord(
                tenant.Id,
                "auth.register.succeeded",
                "success",
                user.Id,
                session?.Id,
                user.Email,
                session?.IpAddress,
                session?.UserAgent,
                correlationId,
                traceId),
            cancellationToken);

        var userRegistered = new UserRegisteredV1(
            user.Id,
            user.TenantId,
            user.UserName,
            user.Email ?? string.Empty,
            user.FirstName,
            user.LastName,
            utcNow,
            culture);

        await integrationEventOutbox.AddAsync(
            Guid.NewGuid(),
            UserRegisteredV1.EventName,
            UserRegisteredV1.EventVersion,
            UserRegisteredV1.RoutingKey,
            "Norge360.Auth",
            userRegistered,
            correlationId,
            traceId,
            utcNow,
            cancellationToken);

        await integrationEventOutbox.AddAsync(
            Guid.NewGuid(),
            AuthEmailConfirmationRequestedV1.EventName,
            AuthEmailConfirmationRequestedV1.EventVersion,
            AuthEmailConfirmationRequestedV1.RoutingKey,
            "Norge360.Auth",
            new AuthEmailConfirmationRequestedV1(
                user.Id,
                user.TenantId,
                user.UserName,
                user.Email ?? string.Empty,
                emailConfirmationToken,
                AccountLifecycleLinkBuilder.Build(lifecycle.PublicAppBaseUrl, lifecycle.ConfirmEmailPath, user.TenantId, user.Id, emailConfirmationToken, user.Email),
                emailConfirmationExpiresAt,
                culture),
            correlationId,
            traceId,
            utcNow,
            cancellationToken);

        try
        {
            await unitOfWork.SaveChangesAsync(cancellationToken);
        }
        catch (DbUpdateException)
        {
            throw RegistrationConflict();
        }

        foreach (var sessionId in revokedSessionIds)
        {
            userSessionStateValidator.Evict(tenant.Id, sessionId);
        }

        if (session is null || refreshToken is null)
        {
            return new AuthSessionResult.PendingConfirmation(tenant.Id, user.Id, user.Email ?? string.Empty);
        }

        AuthMetrics.AuthSucceeded.Add(1, new KeyValuePair<string, object?>("flow", "register"));

        var accessToken = accessTokenFactory.Create(user, tenant.Id, session.Id);
        return new AuthSessionResult.Issued(
            new AuthenticationTokenResponse(
                accessToken.Token,
                accessToken.ExpiresAtUtc,
                refreshToken.Token,
                refreshToken.ExpiresAtUtc,
                tenant.Id,
                user.Id,
                user.UserName,
                user.Email ?? string.Empty,
                session.Id,
                IsPersistent: true));
    }

    private static AuthApplicationException RegistrationConflict() =>
        new(
            "Registration could not be completed",
            "The registration request could not be completed with the supplied identity.",
            (int)HttpStatusCode.Conflict,
            errorCode: "registration_conflict",
            type: "https://httpstatuses.com/409");

    private static AuthApplicationException DuplicateEmailConflict() =>
        new(
            "Registration could not be completed",
            "An account with this email address already exists.",
            (int)HttpStatusCode.Conflict,
            errorCode: "duplicate_email",
            type: "https://httpstatuses.com/409");

    private static string JoinDistinct(IEnumerable<string> values) =>
        string.Join(',', values.Where(value => !string.IsNullOrWhiteSpace(value)).Distinct(StringComparer.OrdinalIgnoreCase));

    private static string CreateUniqueSlug(string tenantName)
    {
        var normalized = SlugUnsafeCharacters().Replace(tenantName.Trim().ToLowerInvariant(), "-").Trim('-');
        if (string.IsNullOrWhiteSpace(normalized))
        {
            normalized = "workspace";
        }

        if (normalized.Length > 70)
        {
            normalized = normalized[..70].Trim('-');
        }

        return $"{normalized}-{Guid.NewGuid():N}"[..Math.Min(normalized.Length + 9, 80)];
    }

    [GeneratedRegex("[^a-z0-9]+", RegexOptions.CultureInvariant)]
    private static partial Regex SlugUnsafeCharacters();
}
