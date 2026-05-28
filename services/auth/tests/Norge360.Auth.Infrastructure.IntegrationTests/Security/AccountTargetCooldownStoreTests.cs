// <copyright file="AccountTargetCooldownStoreTests.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using FluentAssertions;
using Microsoft.Extensions.Caching.Distributed;
using Microsoft.Extensions.Caching.Memory;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;
using Norge360.Auth.Infrastructure.Services;
using Norge360.Auth.TestKit.Logging;

namespace Norge360.Auth.Infrastructure.IntegrationTests.Security;

public sealed class AccountTargetCooldownStoreTests
{
    [Fact]
    public async Task TryAcquireAsync_Should_Return_True_On_First_Request_And_False_While_Cooldown_Is_Active()
    {
        var store = CreateSut();
        var tenantId = Guid.NewGuid();

        var first = await store.TryAcquireAsync("password-reset", tenantId, "USER@EXAMPLE.COM", 60, CancellationToken.None);
        var second = await store.TryAcquireAsync("password-reset", tenantId, "USER@EXAMPLE.COM", 60, CancellationToken.None);

        first.Should().BeTrue();
        second.Should().BeFalse();
    }

    [Fact]
    public async Task TryAcquireAsync_Should_Return_False_When_CacheGet_Fails_And_Log()
    {
        var sink = new TestLogSink();
        var store = CreateSut(cache: new ThrowingDistributedCache(throwOnGet: true), logSink: sink);

        var acquired = await store.TryAcquireAsync("password-reset", Guid.NewGuid(), "USER@EXAMPLE.COM", 60, CancellationToken.None);

        acquired.Should().BeFalse();
        sink.Entries.Should().Contain(entry =>
            entry.Level == LogLevel.Error &&
            entry.Message.Contains("Account target cooldown cache get failed", StringComparison.Ordinal));
    }

    [Fact]
    public async Task TryAcquireAsync_Should_Return_False_When_CacheSet_Fails_And_Log()
    {
        var sink = new TestLogSink();
        var store = CreateSut(cache: new ThrowingDistributedCache(throwOnSet: true), logSink: sink);

        var acquired = await store.TryAcquireAsync("email-confirmation-resend", Guid.NewGuid(), "USER@EXAMPLE.COM", 60, CancellationToken.None);

        acquired.Should().BeFalse();
        sink.Entries.Should().Contain(entry =>
            entry.Level == LogLevel.Error &&
            entry.Message.Contains("Account target cooldown cache set failed", StringComparison.Ordinal));
    }

    private static AccountTargetCooldownStore CreateSut(
        IDistributedCache? cache = null,
        TestLogSink? logSink = null)
    {
        cache ??= new MemoryDistributedCache(Options.Create(new MemoryDistributedCacheOptions()));
        ILogger<AccountTargetCooldownStore> logger;
        if (logSink is null)
        {
            logger = NullLogger<AccountTargetCooldownStore>.Instance;
        }
        else
        {
            var factory = LoggerFactory.Create(builder => builder.AddProvider(logSink));
            logger = factory.CreateLogger<AccountTargetCooldownStore>();
        }

        return new AccountTargetCooldownStore(cache, logger);
    }

    private sealed class ThrowingDistributedCache(
        bool throwOnGet = false,
        bool throwOnSet = false) : IDistributedCache
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
        }

        public Task RemoveAsync(string key, CancellationToken token = default) => Task.CompletedTask;

        public void Set(string key, byte[] value, DistributedCacheEntryOptions options)
        {
            if (throwOnSet)
            {
                throw new InvalidOperationException("cache-set-failure");
            }
        }

        public Task SetAsync(string key, byte[] value, DistributedCacheEntryOptions options, CancellationToken token = default)
        {
            if (throwOnSet)
            {
                throw new InvalidOperationException("cache-set-failure");
            }

            return Task.CompletedTask;
        }
    }
}
