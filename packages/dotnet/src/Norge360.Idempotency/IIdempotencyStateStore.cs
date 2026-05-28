// <copyright file="IIdempotencyStateStore.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

namespace Norge360.Idempotency;

public interface IIdempotencyStateStore
{
    Task<IdempotencyState?> GetAsync(string key, CancellationToken cancellationToken);

    Task<bool> TryMarkInProgressAsync(string key, string requestHash, TimeSpan ttl, CancellationToken cancellationToken);

    Task MarkCompletedAsync(string key, string requestHash, string responseJson, TimeSpan ttl, CancellationToken cancellationToken);

    Task RemoveAsync(string key, CancellationToken cancellationToken);
}
