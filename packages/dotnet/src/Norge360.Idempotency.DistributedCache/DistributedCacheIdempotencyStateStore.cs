// <copyright file="DistributedCacheIdempotencyStateStore.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using System.Text.Json;
using Microsoft.Extensions.Caching.Distributed;

namespace Norge360.Idempotency.DistributedCache;

public sealed class DistributedCacheIdempotencyStateStore(IDistributedCache cache) : IIdempotencyStateStore
{
    private static readonly JsonSerializerOptions SerializerOptions = new(JsonSerializerDefaults.Web);

    public async Task<IdempotencyState?> GetAsync(string key, CancellationToken cancellationToken)
    {
        var payload = await cache.GetStringAsync(key, cancellationToken);
        return string.IsNullOrWhiteSpace(payload)
            ? null
            : JsonSerializer.Deserialize<IdempotencyState>(payload, SerializerOptions);
    }

    public async Task<bool> TryMarkInProgressAsync(string key, string requestHash, TimeSpan ttl, CancellationToken cancellationToken)
    {
        if (await GetAsync(key, cancellationToken) is not null)
        {
            return false;
        }

        await cache.SetStringAsync(
            key,
            JsonSerializer.Serialize(IdempotencyState.InProgress(requestHash), SerializerOptions),
            new DistributedCacheEntryOptions { AbsoluteExpirationRelativeToNow = ttl },
            cancellationToken);

        return true;
    }

    public Task MarkCompletedAsync(string key, string requestHash, string responseJson, TimeSpan ttl, CancellationToken cancellationToken)
        => cache.SetStringAsync(
            key,
            JsonSerializer.Serialize(IdempotencyState.Completed(requestHash, responseJson), SerializerOptions),
            new DistributedCacheEntryOptions { AbsoluteExpirationRelativeToNow = ttl },
            cancellationToken);

    public Task RemoveAsync(string key, CancellationToken cancellationToken)
        => cache.RemoveAsync(key, cancellationToken);
}
