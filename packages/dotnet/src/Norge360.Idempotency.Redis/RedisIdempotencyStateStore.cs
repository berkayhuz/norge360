// <copyright file="RedisIdempotencyStateStore.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using System.Text.Json;
using StackExchange.Redis;

namespace Norge360.Idempotency.Redis;

public sealed class RedisIdempotencyStateStore(IConnectionMultiplexer connectionMultiplexer) : IIdempotencyStateStore
{
    private static readonly JsonSerializerOptions SerializerOptions = new(JsonSerializerDefaults.Web);

    public async Task<IdempotencyState?> GetAsync(string key, CancellationToken cancellationToken)
    {
        var value = await connectionMultiplexer.GetDatabase().StringGetAsync(key);
        return value.HasValue
            ? JsonSerializer.Deserialize<IdempotencyState>(value.ToString(), SerializerOptions)
            : null;
    }

    public Task<bool> TryMarkInProgressAsync(string key, string requestHash, TimeSpan ttl, CancellationToken cancellationToken)
        => connectionMultiplexer
            .GetDatabase()
            .StringSetAsync(
                key,
                JsonSerializer.Serialize(IdempotencyState.InProgress(requestHash), SerializerOptions),
                ttl,
                When.NotExists);

    public Task MarkCompletedAsync(string key, string requestHash, string responseJson, TimeSpan ttl, CancellationToken cancellationToken)
        => connectionMultiplexer
            .GetDatabase()
            .StringSetAsync(
                key,
                JsonSerializer.Serialize(IdempotencyState.Completed(requestHash, responseJson), SerializerOptions),
                ttl,
                When.Always);

    public async Task RemoveAsync(string key, CancellationToken cancellationToken)
        => await connectionMultiplexer.GetDatabase().KeyDeleteAsync(key);
}
