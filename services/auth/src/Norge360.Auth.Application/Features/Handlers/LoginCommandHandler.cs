using MediatR;
using Microsoft.AspNetCore.Identity;
using Norge360.Auth.Application.Abstractions;
using Norge360.Auth.Application.Features.Commands;
using Norge360.Auth.Application.Helpers;
using Norge360.Auth.Contracts.Responses;
using Norge360.Auth.Domain.Entities;
using Norge360.Clock;

namespace Norge360.Auth.Application.Features.Handlers;

public sealed class LoginCommandHandler(
    IUserRepository userRepository,
    IUserSessionRepository userSessionRepository,
    IAuthUnitOfWork unitOfWork,
    IPasswordHasher<User> passwordHasher,
    IAccessTokenFactory accessTokenFactory,
    IRefreshTokenService refreshTokenService,
    IClock clock)
    : IRequestHandler<LoginCommand, AuthenticationTokenResponse>
{
    public async Task<AuthenticationTokenResponse> Handle(LoginCommand request, CancellationToken cancellationToken)
    {
        var normalizedIdentity = AuthenticationNormalization.Normalize(request.EmailOrUserName);
        var user = await userRepository.FindByIdentityAsync(normalizedIdentity, cancellationToken)
            ?? throw new InvalidOperationException("invalid_credentials");

        var verification = passwordHasher.VerifyHashedPassword(user, user.PasswordHash, request.Password);
        if (verification == PasswordVerificationResult.Failed)
        {
            throw new InvalidOperationException("invalid_credentials");
        }

        var utcNow = clock.UtcDateTime;
        user.LastLoginAt = utcNow;
        var refreshToken = refreshTokenService.Generate(request.RememberMe);
        var session = new UserSession
        {
            UserId = user.Id,
            IsPersistent = request.RememberMe,
            RefreshTokenFamilyId = Guid.NewGuid(),
            RefreshTokenHash = refreshToken.Hash,
            RefreshTokenExpiresAt = refreshToken.ExpiresAtUtc,
            CreatedAt = utcNow,
            LastSeenAt = utcNow,
            LastRefreshedAt = utcNow
        };

        await userSessionRepository.AddAsync(session, cancellationToken);
        await unitOfWork.SaveChangesAsync(cancellationToken);

        var accessToken = accessTokenFactory.Create(user, session.Id);
        return new AuthenticationTokenResponse(
            accessToken.Token,
            accessToken.ExpiresAtUtc,
            refreshToken.Token,
            refreshToken.ExpiresAtUtc,
            user.Id,
            user.UserName,
            user.Email ?? string.Empty,
            session.Id,
            request.RememberMe);
    }
}
