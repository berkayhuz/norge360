// <copyright file="UserTokenStateValidatorTests.cs" company="Norge360">
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

namespace Norge360.Auth.Infrastructure.IntegrationTests.Security;

public sealed class UserTokenStateValidatorTests
{
    [Fact]
    public async Task IsValidAsync_Should_Fail_After_Membership_Disabled_And_Explicit_Evict()
    {
        var tenantId = Guid.NewGuid();
        var userId = Guid.NewGuid();
        var repository = new MutableTokenStateRepository(new ActiveUserTokenState(7));
        var validator = CreateSut(repository);

        var first = await validator.IsValidAsync(tenantId, userId, 7, CancellationToken.None);
        first.Should().BeTrue();

        repository.CurrentState = null;
        validator.Evict(tenantId, userId);

        var second = await validator.IsValidAsync(tenantId, userId, 7, CancellationToken.None);
        second.Should().BeFalse();
        repository.GetCallCount.Should().Be(2);
    }

    [Fact]
    public async Task IsValidAsync_Should_Not_Remain_Valid_Longer_Than_Configured_Ttl_When_Tenant_Disabled()
    {
        var tenantId = Guid.NewGuid();
        var userId = Guid.NewGuid();
        var repository = new MutableTokenStateRepository(new ActiveUserTokenState(3));
        var validator = CreateSut(
            repository,
            new TokenValidationCacheOptions
            {
                EnableCache = true,
                AbsoluteExpirationSeconds = 1,
                NegativeAbsoluteExpirationSeconds = 1,
                KeyPrefix = "auth:tests"
            });

        var first = await validator.IsValidAsync(tenantId, userId, 3, CancellationToken.None);
        first.Should().BeTrue();

        repository.CurrentState = null;

        var immediate = await validator.IsValidAsync(tenantId, userId, 3, CancellationToken.None);
        immediate.Should().BeTrue("positive cache may remain valid until TTL when no explicit eviction is available");

        await Task.Delay(TimeSpan.FromMilliseconds(1300));

        var afterTtl = await validator.IsValidAsync(tenantId, userId, 3, CancellationToken.None);
        afterTtl.Should().BeFalse();
        repository.GetCallCount.Should().Be(2);
    }

    [Fact]
    public async Task IsValidAsync_Should_Reject_Old_TokenVersion_After_SecurityState_Change_And_Evict()
    {
        var tenantId = Guid.NewGuid();
        var userId = Guid.NewGuid();
        var repository = new MutableTokenStateRepository(new ActiveUserTokenState(1));
        var validator = CreateSut(repository);

        var first = await validator.IsValidAsync(tenantId, userId, 1, CancellationToken.None);
        first.Should().BeTrue();

        repository.CurrentState = new ActiveUserTokenState(2);
        validator.Evict(tenantId, userId);

        var oldToken = await validator.IsValidAsync(tenantId, userId, 1, CancellationToken.None);
        var newToken = await validator.IsValidAsync(tenantId, userId, 2, CancellationToken.None);

        oldToken.Should().BeFalse();
        newToken.Should().BeTrue();
        repository.GetCallCount.Should().Be(2);
    }

    [Fact]
    public async Task CacheGetFailure_Should_Fallback_To_Repository_And_Log()
    {
        var tenantId = Guid.NewGuid();
        var userId = Guid.NewGuid();
        var sink = new TestLogSink();
        var repository = new MutableTokenStateRepository(new ActiveUserTokenState(5));
        var validator = CreateSut(repository, cache: new ThrowingDistributedCache(throwOnGet: true), logSink: sink);

        var result = await validator.IsValidAsync(tenantId, userId, 5, CancellationToken.None);

        result.Should().BeTrue();
        repository.GetCallCount.Should().Be(1);
        sink.Contains("Token validation cache get failed").Should().BeTrue();
    }

    [Fact]
    public async Task CacheSetFailure_Should_Not_Allow_Invalid_State_And_Log()
    {
        var tenantId = Guid.NewGuid();
        var userId = Guid.NewGuid();
        var sink = new TestLogSink();
        var repository = new MutableTokenStateRepository(initialState: null);
        var validator = CreateSut(repository, cache: new ThrowingDistributedCache(throwOnSet: true), logSink: sink);

        var result = await validator.IsValidAsync(tenantId, userId, 1, CancellationToken.None);

        result.Should().BeFalse();
        repository.GetCallCount.Should().Be(1);
        sink.Contains("Token validation cache set failed").Should().BeTrue();
    }

    [Fact]
    public void CacheEvictFailure_Should_Be_Logged()
    {
        var tenantId = Guid.NewGuid();
        var userId = Guid.NewGuid();
        var sink = new TestLogSink();
        var repository = new MutableTokenStateRepository(new ActiveUserTokenState(1));
        var validator = CreateSut(repository, cache: new ThrowingDistributedCache(throwOnRemove: true), logSink: sink);

        validator.Evict(tenantId, userId);

        sink.Entries.Should().Contain(entry =>
            entry.Level == LogLevel.Error &&
            entry.Message.Contains("Token validation cache evict failed", StringComparison.Ordinal));
    }

    private static UserTokenStateValidator CreateSut(
        MutableTokenStateRepository repository,
        TokenValidationCacheOptions? optionsOverride = null,
        IDistributedCache? cache = null,
        TestLogSink? logSink = null)
    {
        cache ??= new MemoryDistributedCache(Options.Create(new MemoryDistributedCacheOptions()));
        var options = Options.Create(optionsOverride ?? new TokenValidationCacheOptions
        {
            EnableCache = true,
            AbsoluteExpirationSeconds = 15,
            NegativeAbsoluteExpirationSeconds = 10,
            KeyPrefix = "auth:tests"
        });

        ILogger<UserTokenStateValidator> logger;
        if (logSink is null)
        {
            logger = NullLogger<UserTokenStateValidator>.Instance;
        }
        else
        {
            var factory = LoggerFactory.Create(builder => builder.AddProvider(logSink));
            logger = factory.CreateLogger<UserTokenStateValidator>();
        }

        return new UserTokenStateValidator(repository, cache, options, logger);
    }

    private sealed class MutableTokenStateRepository(ActiveUserTokenState? initialState) : IUserRepository
    {
        public ActiveUserTokenState? CurrentState { get; set; } = initialState;

        public int GetCallCount { get; private set; }

        public Task<ActiveUserTokenState?> GetActiveTokenStateAsync(Guid tenantId, Guid userId, CancellationToken cancellationToken)
        {
            GetCallCount++;
            return Task.FromResult(CurrentState);
        }

        public Task<User?> FindByTenantAndIdentityAsync(Guid tenantId, string normalizedIdentity, CancellationToken cancellationToken) => throw new NotSupportedException();
        public Task<User?> FindByIdentityAsync(string normalizedIdentity, CancellationToken cancellationToken) => throw new NotSupportedException();
        public Task<LoginScopeResolution?> ResolveLoginScopeByIdentityAsync(string normalizedIdentity, CancellationToken cancellationToken) => throw new NotSupportedException();
        public Task<User?> GetActiveByIdAsync(Guid tenantId, Guid userId, CancellationToken cancellationToken) => throw new NotSupportedException();
        public Task<User?> GetByIdAsync(Guid tenantId, Guid userId, CancellationToken cancellationToken) => throw new NotSupportedException();
        public Task<User?> GetByIdIncludingInactiveAsync(Guid tenantId, Guid userId, CancellationToken cancellationToken) => throw new NotSupportedException();
        public Task<UserTenantMembership?> GetMembershipAsync(Guid tenantId, Guid userId, CancellationToken cancellationToken) => throw new NotSupportedException();
        public Task<IReadOnlyCollection<UserTenantMembershipSnapshot>> ListMembershipsByUserAsync(Guid userId, CancellationToken cancellationToken) => throw new NotSupportedException();
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
