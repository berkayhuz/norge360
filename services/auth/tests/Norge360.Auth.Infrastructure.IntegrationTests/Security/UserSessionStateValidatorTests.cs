// <copyright file="UserSessionStateValidatorTests.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using FluentAssertions;
using Microsoft.Extensions.Caching.Distributed;
using Microsoft.Extensions.Caching.Memory;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;
using Norge360.Auth.Application.Abstractions;
using Norge360.Auth.Application.Options;
using Norge360.Auth.Domain.Entities;
using Norge360.Auth.Infrastructure.Services;
using Norge360.Auth.TestKit.Logging;
using Norge360.Clock;

namespace Norge360.Auth.Infrastructure.IntegrationTests.Security;

public sealed class UserSessionStateValidatorTests
{
    [Fact]
    public async Task IsValidAsync_Should_Cache_Valid_Session_And_Avoid_Second_Repository_Read()
    {
        var tenantId = Guid.NewGuid();
        var userId = Guid.NewGuid();
        var now = Utc(2026, 1, 15, 10, 0, 0);
        var session = CreateSession(tenantId, userId, now);
        var repository = new InMemorySessionRepository([session]);
        var validator = CreateSut(repository, now);

        var first = await validator.IsValidAsync(tenantId, userId, session.Id, CancellationToken.None);
        var second = await validator.IsValidAsync(tenantId, userId, session.Id, CancellationToken.None);

        first.Should().BeTrue();
        second.Should().BeTrue();
        repository.GetCallCount.Should().Be(1);
    }

    [Fact]
    public async Task IsValidAsync_Should_Cache_Invalid_Session_And_Avoid_Second_Repository_Read()
    {
        var tenantId = Guid.NewGuid();
        var userId = Guid.NewGuid();
        var now = Utc(2026, 1, 15, 10, 0, 0);
        var session = CreateSession(tenantId, userId, now);
        session.Revoke(now.AddMinutes(-5), "logout");

        var repository = new InMemorySessionRepository([session]);
        var validator = CreateSut(repository, now);

        var first = await validator.IsValidAsync(tenantId, userId, session.Id, CancellationToken.None);
        var second = await validator.IsValidAsync(tenantId, userId, session.Id, CancellationToken.None);

        first.Should().BeFalse();
        second.Should().BeFalse();
        repository.GetCallCount.Should().Be(1);
    }

    [Fact]
    public async Task Evict_Should_Remove_Cached_State_And_Force_Fresh_Repository_Read()
    {
        var tenantId = Guid.NewGuid();
        var userId = Guid.NewGuid();
        var now = Utc(2026, 1, 15, 10, 0, 0);
        var session = CreateSession(tenantId, userId, now);
        var repository = new InMemorySessionRepository([session]);
        var validator = CreateSut(repository, now);

        await validator.IsValidAsync(tenantId, userId, session.Id, CancellationToken.None);
        validator.Evict(tenantId, session.Id);
        await validator.IsValidAsync(tenantId, userId, session.Id, CancellationToken.None);

        repository.GetCallCount.Should().Be(2);
    }

    [Fact]
    public async Task IsValidAsync_Should_Reject_When_UserId_Does_Not_Match_SessionOwner()
    {
        var tenantId = Guid.NewGuid();
        var ownerId = Guid.NewGuid();
        var otherUserId = Guid.NewGuid();
        var now = Utc(2026, 1, 15, 10, 0, 0);
        var session = CreateSession(tenantId, ownerId, now);
        var repository = new InMemorySessionRepository([session]);
        var validator = CreateSut(repository, now);

        var ownerResult = await validator.IsValidAsync(tenantId, ownerId, session.Id, CancellationToken.None);
        var otherUserResult = await validator.IsValidAsync(tenantId, otherUserId, session.Id, CancellationToken.None);

        ownerResult.Should().BeTrue();
        otherUserResult.Should().BeFalse();
        repository.GetCallCount.Should().Be(2);
    }

    [Fact]
    public async Task IsValidAsync_Should_Return_False_After_Session_Revoke_And_Evict()
    {
        var tenantId = Guid.NewGuid();
        var userId = Guid.NewGuid();
        var now = Utc(2026, 1, 15, 10, 0, 0);
        var session = CreateSession(tenantId, userId, now);
        var repository = new InMemorySessionRepository([session]);
        var validator = CreateSut(repository, now);

        var cachedValid = await validator.IsValidAsync(tenantId, userId, session.Id, CancellationToken.None);
        cachedValid.Should().BeTrue();

        session.Revoke(now.AddMinutes(1), "logout");
        validator.Evict(tenantId, session.Id);

        var revokedResult = await validator.IsValidAsync(tenantId, userId, session.Id, CancellationToken.None);

        revokedResult.Should().BeFalse();
        repository.GetCallCount.Should().Be(2);
    }

    [Fact]
    public async Task IsValidAsync_Should_Not_Collide_Between_Tenants_For_Same_User()
    {
        var tenantA = Guid.NewGuid();
        var tenantB = Guid.NewGuid();
        var userId = Guid.NewGuid();
        var now = Utc(2026, 1, 15, 10, 0, 0);
        var sessionA = CreateSession(tenantA, userId, now);
        var sessionB = CreateSession(tenantB, userId, now);
        var repository = new InMemorySessionRepository([sessionA, sessionB]);
        var validator = CreateSut(repository, now);

        var tenantAFirst = await validator.IsValidAsync(tenantA, userId, sessionA.Id, CancellationToken.None);
        var tenantBFirst = await validator.IsValidAsync(tenantB, userId, sessionB.Id, CancellationToken.None);
        var tenantASecond = await validator.IsValidAsync(tenantA, userId, sessionA.Id, CancellationToken.None);
        var tenantBSecond = await validator.IsValidAsync(tenantB, userId, sessionB.Id, CancellationToken.None);

        tenantAFirst.Should().BeTrue();
        tenantBFirst.Should().BeTrue();
        tenantASecond.Should().BeTrue();
        tenantBSecond.Should().BeTrue();
        repository.GetCallCount.Should().Be(2);
    }

    [Fact]
    public async Task IsValidAsync_Should_Requery_When_Valid_Cache_Ttl_Expires()
    {
        var tenantId = Guid.NewGuid();
        var userId = Guid.NewGuid();
        var now = Utc(2026, 1, 15, 10, 0, 0);
        var session = CreateSession(tenantId, userId, now);
        var repository = new InMemorySessionRepository([session]);
        var validator = CreateSut(
            repository,
            now,
            new TokenValidationCacheOptions
            {
                EnableCache = true,
                AbsoluteExpirationSeconds = 1,
                NegativeAbsoluteExpirationSeconds = 1,
                KeyPrefix = "auth:tests"
            });

        var first = await validator.IsValidAsync(tenantId, userId, session.Id, CancellationToken.None);
        await Task.Delay(TimeSpan.FromMilliseconds(1300));
        var second = await validator.IsValidAsync(tenantId, userId, session.Id, CancellationToken.None);

        first.Should().BeTrue();
        second.Should().BeTrue();
        repository.GetCallCount.Should().Be(2);
    }

    [Fact]
    public async Task SessionCacheGetFailure_Should_Fallback_To_Repository_And_Log()
    {
        var tenantId = Guid.NewGuid();
        var userId = Guid.NewGuid();
        var now = Utc(2026, 1, 15, 10, 0, 0);
        var session = CreateSession(tenantId, userId, now);
        var repository = new InMemorySessionRepository([session]);
        var sink = new TestLogSink();
        var validator = CreateSut(
            repository,
            now,
            cache: new ThrowingDistributedCache(throwOnGet: true),
            logSink: sink);

        var result = await validator.IsValidAsync(tenantId, userId, session.Id, CancellationToken.None);

        result.Should().BeTrue();
        repository.GetCallCount.Should().Be(1);
        sink.Contains("Session validation cache get failed").Should().BeTrue();
    }

    [Fact]
    public void SessionCacheEvictFailure_Should_Be_Logged()
    {
        var tenantId = Guid.NewGuid();
        var sessionId = Guid.NewGuid();
        var now = Utc(2026, 1, 15, 10, 0, 0);
        var sink = new TestLogSink();
        var validator = CreateSut(
            new InMemorySessionRepository([]),
            now,
            cache: new ThrowingDistributedCache(throwOnRemove: true),
            logSink: sink);

        validator.Evict(tenantId, sessionId);

        sink.Entries.Should().Contain(entry =>
            entry.Level == LogLevel.Error &&
            entry.Message.Contains("Session validation cache evict failed", StringComparison.Ordinal));
    }

    private static DateTime Utc(int year, int month, int day, int hour, int minute, int second) =>
        new(year, month, day, hour, minute, second, DateTimeKind.Utc);

    private static UserSession CreateSession(Guid tenantId, Guid userId, DateTime now) =>
        new()
        {
            TenantId = tenantId,
            UserId = userId,
            RefreshTokenFamilyId = Guid.NewGuid(),
            RefreshTokenHash = "hash",
            RefreshTokenExpiresAt = now.AddHours(1),
            CreatedAt = now.AddMinutes(-30)
        };

    private static UserSessionStateValidator CreateSut(
        InMemorySessionRepository repository,
        DateTime now,
        TokenValidationCacheOptions? optionsOverride = null,
        IDistributedCache? cache = null,
        TestLogSink? logSink = null)
    {
        cache ??= new MemoryDistributedCache(Options.Create(new MemoryDistributedCacheOptions()));
        var options = Options.Create(optionsOverride ?? new TokenValidationCacheOptions
        {
            EnableCache = true,
            AbsoluteExpirationSeconds = 30,
            NegativeAbsoluteExpirationSeconds = 10,
            KeyPrefix = "auth:tests"
        });

        ILogger<UserSessionStateValidator> logger;
        if (logSink is null)
        {
            logger = NullLogger<UserSessionStateValidator>.Instance;
        }
        else
        {
            var factory = LoggerFactory.Create(builder => builder.AddProvider(logSink));
            logger = factory.CreateLogger<UserSessionStateValidator>();
        }

        return new UserSessionStateValidator(
            repository,
            new StaticAuthSessionService(),
            cache,
            options,
            new FixedClock(now),
            logger);
    }

    private sealed class InMemorySessionRepository(IEnumerable<UserSession> sessions) : IUserSessionRepository
    {
        private readonly Dictionary<(Guid TenantId, Guid SessionId), UserSession> _sessions = sessions.ToDictionary(
            session => (session.TenantId, session.Id),
            session => session);

        public int GetCallCount { get; private set; }

        public Task<UserSession?> GetAsync(Guid tenantId, Guid sessionId, CancellationToken cancellationToken)
        {
            GetCallCount++;
            _sessions.TryGetValue((tenantId, sessionId), out var session);
            return Task.FromResult(session);
        }

        public Task<UserSession?> GetWithUserAsync(Guid tenantId, Guid sessionId, CancellationToken cancellationToken) => GetAsync(tenantId, sessionId, cancellationToken);
        public Task<IReadOnlyCollection<UserSession>> ListForUserAsync(Guid tenantId, Guid userId, CancellationToken cancellationToken) => throw new NotSupportedException();
        public Task AddAsync(UserSession session, CancellationToken cancellationToken) => throw new NotSupportedException();
        public Task<bool> RevokeAsync(Guid tenantId, Guid userId, Guid sessionId, DateTime utcNow, string reason, CancellationToken cancellationToken) => throw new NotSupportedException();
        public Task<IReadOnlyCollection<Guid>> RevokeAllAsync(Guid tenantId, Guid userId, DateTime utcNow, string reason, Guid? excludedSessionId, CancellationToken cancellationToken) => throw new NotSupportedException();
    }

    private sealed class StaticAuthSessionService : IAuthSessionService
    {
        public Task<IReadOnlyCollection<Guid>> EnforceSessionLimitsAsync(Guid tenantId, Guid userId, Guid? currentSessionId, CancellationToken cancellationToken) =>
            Task.FromResult<IReadOnlyCollection<Guid>>([]);

        public bool IsExpired(UserSession session, DateTime utcNow) => utcNow >= session.RefreshTokenExpiresAt;
    }

    private sealed class FixedClock(DateTime utcNow) : IClock
    {
        public DateTimeOffset UtcNow { get; } = new(utcNow, TimeSpan.Zero);
        public DateTime UtcDateTime { get; } = utcNow;
    }

    private sealed class ThrowingDistributedCache(
        bool throwOnGet = false,
        bool throwOnSet = false,
        bool throwOnRemove = false) : IDistributedCache
    {
        public byte[]? Get(string key)
        {
            if (throwOnGet)
            {
                throw new InvalidOperationException("cache-get-failure");
            }

            return null;
        }

        public Task<byte[]?> GetAsync(string key, CancellationToken token = default)
        {
            if (throwOnGet)
            {
                throw new InvalidOperationException("cache-get-failure");
            }

            return Task.FromResult<byte[]?>(null);
        }

        public void Refresh(string key)
        {
        }

        public Task RefreshAsync(string key, CancellationToken token = default) => Task.CompletedTask;

        public void Remove(string key)
        {
            if (throwOnRemove)
            {
                throw new InvalidOperationException("cache-remove-failure");
            }
        }

        public Task RemoveAsync(string key, CancellationToken token = default)
        {
            Remove(key);
            return Task.CompletedTask;
        }

        public void Set(string key, byte[] value, DistributedCacheEntryOptions options)
        {
            if (throwOnSet)
            {
                throw new InvalidOperationException("cache-set-failure");
            }
        }

        public Task SetAsync(string key, byte[] value, DistributedCacheEntryOptions options, CancellationToken token = default)
        {
            Set(key, value, options);
            return Task.CompletedTask;
        }
    }
}
