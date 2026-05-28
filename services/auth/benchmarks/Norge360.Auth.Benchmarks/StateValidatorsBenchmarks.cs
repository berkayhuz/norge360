// <copyright file="StateValidatorsBenchmarks.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using BenchmarkDotNet.Attributes;
using Microsoft.Extensions.Caching.Distributed;
using Microsoft.Extensions.Caching.Memory;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;
using Norge360.Auth.Application.Abstractions;
using Norge360.Auth.Application.Options;
using Norge360.Auth.Domain.Entities;
using Norge360.Auth.Infrastructure.Services;
using Norge360.Clock;

namespace Norge360.Auth.Benchmarks;

[MemoryDiagnoser]
public class StateValidatorsBenchmarks
{
    private UserTokenStateValidator _tokenValidator = default!;
    private UserSessionStateValidator _sessionValidator = default!;
    private Guid _tenantId;
    private Guid _userId;
    private Guid _sessionId;

    [GlobalSetup]
    public void Setup()
    {
        _tenantId = Guid.NewGuid();
        _userId = Guid.NewGuid();
        _sessionId = Guid.NewGuid();

        var options = Options.Create(new TokenValidationCacheOptions
        {
            EnableCache = true,
            AbsoluteExpirationSeconds = 30,
            NegativeAbsoluteExpirationSeconds = 10,
            KeyPrefix = "auth:bench"
        });

        IDistributedCache tokenCache = new MemoryDistributedCache(Options.Create(new MemoryDistributedCacheOptions()));
        IDistributedCache sessionCache = new MemoryDistributedCache(Options.Create(new MemoryDistributedCacheOptions()));

        _tokenValidator = new UserTokenStateValidator(
            new StaticUserRepository(tokenVersion: 3),
            tokenCache,
            options,
            NullLogger<UserTokenStateValidator>.Instance);

        _sessionValidator = new UserSessionStateValidator(
            new StaticUserSessionRepository(_tenantId, _userId),
            new StaticAuthSessionService(),
            sessionCache,
            options,
            new FixedClock(DateTimeOffset.UtcNow),
            NullLogger<UserSessionStateValidator>.Instance);
    }

    [Benchmark]
    public Task<bool> TokenState_IsValid_CacheMiss() =>
        _tokenValidator.IsValidAsync(_tenantId, _userId, tokenVersion: 3, CancellationToken.None);

    [Benchmark]
    public async Task<bool> TokenState_IsValid_CacheHit()
    {
        await _tokenValidator.IsValidAsync(_tenantId, _userId, tokenVersion: 3, CancellationToken.None);
        return await _tokenValidator.IsValidAsync(_tenantId, _userId, tokenVersion: 3, CancellationToken.None);
    }

    [Benchmark]
    public void TokenState_Evict() => _tokenValidator.Evict(_tenantId, _userId);

    [Benchmark]
    public Task<bool> SessionState_IsValid_CacheMiss() =>
        _sessionValidator.IsValidAsync(_tenantId, _userId, _sessionId, CancellationToken.None);

    [Benchmark]
    public async Task<bool> SessionState_IsValid_CacheHit()
    {
        await _sessionValidator.IsValidAsync(_tenantId, _userId, _sessionId, CancellationToken.None);
        return await _sessionValidator.IsValidAsync(_tenantId, _userId, _sessionId, CancellationToken.None);
    }

    [Benchmark]
    public void SessionState_Evict() => _sessionValidator.Evict(_tenantId, _sessionId);

    private sealed class StaticUserRepository(int tokenVersion) : IUserRepository
    {
        public Task<ActiveUserTokenState?> GetActiveTokenStateAsync(Guid tenantId, Guid userId, CancellationToken cancellationToken) =>
            Task.FromResult<ActiveUserTokenState?>(new ActiveUserTokenState(tokenVersion));

        public Task<User?> FindByTenantAndIdentityAsync(Guid tenantId, string normalizedIdentity, CancellationToken cancellationToken) => throw new NotSupportedException();
        public Task<User?> FindByIdentityAsync(string normalizedIdentity, CancellationToken cancellationToken) => throw new NotSupportedException();
        public Task<LoginScopeResolution?> ResolveLoginScopeByIdentityAsync(string normalizedIdentity, CancellationToken cancellationToken) => throw new NotSupportedException();
        public Task<User?> GetActiveByIdAsync(Guid tenantId, Guid userId, CancellationToken cancellationToken) => throw new NotSupportedException();
        public Task<User?> GetByIdAsync(Guid tenantId, Guid userId, CancellationToken cancellationToken) => throw new NotSupportedException();
        public Task<User?> GetByIdIncludingInactiveAsync(Guid tenantId, Guid userId, CancellationToken cancellationToken) => throw new NotSupportedException();
        public Task<UserTenantMembership?> GetMembershipAsync(Guid tenantId, Guid userId, CancellationToken cancellationToken) => throw new NotSupportedException();
        public Task<IReadOnlyCollection<UserTenantMembership>> ListMembershipsByTenantAsync(Guid tenantId, CancellationToken cancellationToken) => throw new NotSupportedException();
        public Task<IReadOnlyCollection<User>> ListByTenantAsync(Guid tenantId, CancellationToken cancellationToken) => throw new NotSupportedException();
        public Task<int> CountActiveUsersInRoleAsync(Guid tenantId, string role, CancellationToken cancellationToken) => throw new NotSupportedException();
        public Task<bool> ExistsByUserNameAsync(Guid tenantId, string normalizedUserName, CancellationToken cancellationToken) => throw new NotSupportedException();
        public Task<bool> ExistsByEmailAsync(Guid tenantId, string normalizedEmail, CancellationToken cancellationToken) => throw new NotSupportedException();
        public Task<bool> ExistsByEmailAsync(string normalizedEmail, CancellationToken cancellationToken) => throw new NotSupportedException();
        public Task<bool> AnyActiveUserInTenantAsync(Guid tenantId, CancellationToken cancellationToken) => throw new NotSupportedException();
        public Task<bool> IsFirstActiveUserInTenantAsync(Guid tenantId, Guid userId, CancellationToken cancellationToken) => throw new NotSupportedException();
        public Task RecordFailedLoginAsync(Guid tenantId, Guid userId, int maxFailedAttempts, DateTime lockoutEndAt, DateTime utcNow, CancellationToken cancellationToken) => throw new NotSupportedException();
        public Task AddAsync(User user, CancellationToken cancellationToken) => throw new NotSupportedException();
        public Task AddMembershipAsync(UserTenantMembership membership, CancellationToken cancellationToken) => throw new NotSupportedException();
    }

    private sealed class StaticUserSessionRepository(Guid tenantId, Guid userId) : IUserSessionRepository
    {
        private readonly UserSession _session = new()
        {
            TenantId = tenantId,
            UserId = userId,
            CreatedAt = DateTime.UtcNow.AddMinutes(-5),
            LastSeenAt = DateTime.UtcNow.AddMinutes(-1),
            RefreshTokenExpiresAt = DateTime.UtcNow.AddHours(1)
        };

        public Task<UserSession?> GetAsync(Guid tenantId, Guid sessionId, CancellationToken cancellationToken) =>
            Task.FromResult<UserSession?>(tenantId == _session.TenantId ? _session : null);

        public Task<UserSession?> GetWithUserAsync(Guid tenantId, Guid sessionId, CancellationToken cancellationToken) => GetAsync(tenantId, sessionId, cancellationToken);
        public Task<IReadOnlyCollection<UserSession>> ListForUserAsync(Guid tenantId, Guid userId, CancellationToken cancellationToken) => throw new NotSupportedException();
        public Task AddAsync(UserSession session, CancellationToken cancellationToken) => throw new NotSupportedException();
        public Task<bool> RevokeAsync(Guid tenantId, Guid userId, Guid sessionId, DateTime utcNow, string reason, CancellationToken cancellationToken) => throw new NotSupportedException();
        public Task<IReadOnlyCollection<Guid>> RevokeAllAsync(Guid tenantId, Guid userId, DateTime utcNow, string reason, Guid? excludedSessionId, CancellationToken cancellationToken) => throw new NotSupportedException();
    }

    private sealed class StaticAuthSessionService : IAuthSessionService
    {
        public Task<IReadOnlyCollection<Guid>> EnforceSessionLimitsAsync(Guid tenantId, Guid userId, Guid? currentSessionId, CancellationToken cancellationToken) =>
            Task.FromResult<IReadOnlyCollection<Guid>>(Array.Empty<Guid>());

        public bool IsExpired(UserSession session, DateTime utcNow) => utcNow >= session.RefreshTokenExpiresAt;
    }

    private sealed class FixedClock(DateTimeOffset now) : IClock
    {
        public DateTimeOffset UtcNow { get; } = now;
        public DateTime UtcDateTime { get; } = now.UtcDateTime;
    }
}
