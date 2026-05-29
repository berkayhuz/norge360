using MediatR;
using Norge360.Auth.Application.Abstractions;
using Norge360.Auth.Application.Features.Commands;
using Norge360.Clock;

namespace Norge360.Auth.Application.Features.Handlers;

public sealed class LogoutCommandHandler(
    IUserSessionRepository userSessionRepository,
    IAuthUnitOfWork unitOfWork,
    IRefreshTokenService refreshTokenService,
    IClock clock)
    : IRequestHandler<LogoutCommand, Unit>
{
    public async Task<Unit> Handle(LogoutCommand request, CancellationToken cancellationToken)
    {
        var session = await userSessionRepository.GetAsync(request.SessionId, cancellationToken)
            ?? throw new InvalidOperationException("session_not_found");

        if (session.IsRevoked)
        {
            return Unit.Value;
        }

        if (!refreshTokenService.Verify(request.RefreshToken, session.RefreshTokenHash))
        {
            throw new InvalidOperationException("invalid_refresh_token");
        }

        session.Revoke(clock.UtcDateTime, "logout");
        await unitOfWork.SaveChangesAsync(cancellationToken);
        return Unit.Value;
    }
}
