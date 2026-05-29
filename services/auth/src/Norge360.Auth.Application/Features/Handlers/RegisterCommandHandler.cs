using MediatR;
using Microsoft.AspNetCore.Identity;
using Norge360.Auth.Application.Abstractions;
using Norge360.Auth.Application.Features.Commands;
using Norge360.Auth.Application.Helpers;
using Norge360.Auth.Application.Records;
using Norge360.Auth.Contracts.Responses;
using Norge360.Auth.Domain.Entities;
using Norge360.Clock;

namespace Norge360.Auth.Application.Features.Handlers;

public sealed class RegisterCommandHandler(
    IUserRepository userRepository,
    IUserSessionRepository userSessionRepository,
    IAuthUnitOfWork unitOfWork,
    IPasswordHasher<User> passwordHasher,
    IAccessTokenFactory accessTokenFactory,
    IRefreshTokenService refreshTokenService,
    IClock clock)
    : IRequestHandler<RegisterCommand, AuthSessionResult>
{
    public async Task<AuthSessionResult> Handle(RegisterCommand request, CancellationToken cancellationToken)
    {
        var utcNow = clock.UtcDateTime;
        var normalizedEmail = AuthenticationNormalization.Normalize(request.Email);
        var normalizedUserName = AuthenticationNormalization.Normalize(request.UserName);

        if (await userRepository.ExistsByEmailAsync(normalizedEmail, cancellationToken) ||
            await userRepository.ExistsByUserNameAsync(normalizedUserName, cancellationToken))
        {
            throw new InvalidOperationException("duplicate_identity");
        }

        var user = new User
        {
            UserName = request.UserName.Trim(),
            NormalizedUserName = normalizedUserName,
            Email = request.Email.Trim(),
            NormalizedEmail = normalizedEmail,
            FirstName = AuthenticationNormalization.CleanOrNull(request.FirstName),
            LastName = AuthenticationNormalization.CleanOrNull(request.LastName),
            EmailConfirmed = false,
            Roles = "user",
            Permissions = "session:self,profile:self",
            CreatedAt = utcNow
        };

        user.PasswordHash = passwordHasher.HashPassword(user, request.Password);

        var refreshToken = refreshTokenService.Generate(true);
        var session = new UserSession
        {
            UserId = user.Id,
            IsPersistent = true,
            RefreshTokenFamilyId = Guid.NewGuid(),
            RefreshTokenHash = refreshToken.Hash,
            RefreshTokenExpiresAt = refreshToken.ExpiresAtUtc,
            CreatedAt = utcNow,
            LastSeenAt = utcNow,
            LastRefreshedAt = utcNow
        };

        await userRepository.AddAsync(user, cancellationToken);
        await userSessionRepository.AddAsync(session, cancellationToken);
        await unitOfWork.SaveChangesAsync(cancellationToken);

        var accessToken = accessTokenFactory.Create(user, session.Id);
        return new AuthSessionResult.Issued(
            new AuthenticationTokenResponse(
                accessToken.Token,
                accessToken.ExpiresAtUtc,
                refreshToken.Token,
                refreshToken.ExpiresAtUtc,
                user.Id,
                user.UserName,
                user.Email ?? string.Empty,
                session.Id,
                IsPersistent: true));
    }
}
