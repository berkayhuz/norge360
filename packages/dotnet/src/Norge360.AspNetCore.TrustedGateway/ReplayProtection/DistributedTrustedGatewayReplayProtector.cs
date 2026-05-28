// <copyright file="DistributedTrustedGatewayReplayProtector.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using Microsoft.Extensions.Caching.Distributed;
using Microsoft.Extensions.Logging;
using Norge360.AspNetCore.TrustedGateway.Abstractions;
using StackExchange.Redis;

namespace Norge360.AspNetCore.TrustedGateway.ReplayProtection;

public sealed class DistributedTrustedGatewayReplayProtector(
    IDistributedCache distributedCache,
    ILogger<DistributedTrustedGatewayReplayProtector> logger,
    IConnectionMultiplexer? connectionMultiplexer = null) : ITrustedGatewayReplayProtector
{
    public async Task<bool> TryRegisterAsync(string keyId, string nonce, TimeSpan ttl, CancellationToken cancellationToken)
    {
        var cacheKey = $"trusted-gateway:replay:{keyId}:{nonce}";

        if (connectionMultiplexer is not null)
        {
            var database = connectionMultiplexer.GetDatabase();
            var acquired = await database.StringSetAsync(cacheKey, "1", ttl, When.NotExists);
            if (!acquired)
            {
                logger.LogWarning("Trusted gateway replay detected for key {KeyId} nonce {Nonce}.", keyId, nonce);
            }

            return acquired;
        }

        var existing = await distributedCache.GetStringAsync(cacheKey, cancellationToken);
        if (!string.IsNullOrWhiteSpace(existing))
        {
            logger.LogWarning("Trusted gateway replay detected for key {KeyId} nonce {Nonce}.", keyId, nonce);
            return false;
        }

        await distributedCache.SetStringAsync(
            cacheKey,
            "1",
            new DistributedCacheEntryOptions
            {
                AbsoluteExpirationRelativeToNow = ttl
            },
            cancellationToken);

        return true;
    }
}
