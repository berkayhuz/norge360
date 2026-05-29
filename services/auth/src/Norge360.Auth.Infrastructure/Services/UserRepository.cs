using Microsoft.EntityFrameworkCore;
using Norge360.Auth.Application.Abstractions;
using Norge360.Auth.Domain.Entities;
using Norge360.Auth.Infrastructure.Persistence;

namespace Norge360.Auth.Infrastructure.Services;

public sealed class UserRepository(AuthDbContext dbContext) : IUserRepository
{
    public Task<User?> FindByIdentityAsync(string normalizedIdentity, CancellationToken cancellationToken) =>
        dbContext.Users.SingleOrDefaultAsync(
            x => !x.IsDeleted &&
                 x.IsActive &&
                 (x.NormalizedEmail == normalizedIdentity || x.NormalizedUserName == normalizedIdentity),
            cancellationToken);

    public Task<User?> GetActiveByIdAsync(Guid userId, CancellationToken cancellationToken) =>
        dbContext.Users.SingleOrDefaultAsync(x => x.Id == userId && !x.IsDeleted && x.IsActive, cancellationToken);

    public Task<User?> GetByIdAsync(Guid userId, CancellationToken cancellationToken) =>
        dbContext.Users.SingleOrDefaultAsync(x => x.Id == userId && !x.IsDeleted, cancellationToken);

    public Task<ActiveUserTokenState?> GetActiveTokenStateAsync(Guid userId, CancellationToken cancellationToken) =>
        dbContext.Users
            .Where(x => x.Id == userId && !x.IsDeleted && x.IsActive)
            .Select(x => new ActiveUserTokenState(x.TokenVersion))
            .SingleOrDefaultAsync(cancellationToken);

    public Task<bool> ExistsByUserNameAsync(string normalizedUserName, CancellationToken cancellationToken) =>
        dbContext.Users.AnyAsync(x => !x.IsDeleted && x.NormalizedUserName == normalizedUserName, cancellationToken);

    public Task<bool> ExistsByEmailAsync(string normalizedEmail, CancellationToken cancellationToken) =>
        dbContext.Users.AnyAsync(x => !x.IsDeleted && x.NormalizedEmail == normalizedEmail, cancellationToken);

    public Task RecordFailedLoginAsync(Guid userId, int maxFailedAttempts, DateTime lockoutEndAt, DateTime utcNow, CancellationToken cancellationToken) =>
        dbContext.Users
            .Where(x => x.Id == userId && !x.IsDeleted)
            .ExecuteUpdateAsync(updates => updates
                .SetProperty(x => x.AccessFailedCount, x => x.AccessFailedCount + 1)
                .SetProperty(x => x.IsLocked, x => x.AccessFailedCount + 1 >= maxFailedAttempts)
                .SetProperty(x => x.LockoutEndAt, x => x.AccessFailedCount + 1 >= maxFailedAttempts ? (DateTime?)lockoutEndAt : x.LockoutEndAt)
                .SetProperty(x => x.UpdatedAt, utcNow), cancellationToken);

    public Task AddAsync(User user, CancellationToken cancellationToken) =>
        dbContext.Users.AddAsync(user, cancellationToken).AsTask();
}
