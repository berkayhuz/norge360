// <copyright file="AccountTargetCooldownStore.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using System.Security.Cryptography;
using System.Text;
using Microsoft.Extensions.Caching.Distributed;
using Microsoft.Extensions.Logging;
using Norge360.Auth.Application.Abstractions;

namespace Norge360.Auth.Infrastructure.Services;

public sealed class AccountTargetCooldownStore(
    IDistributedCache distributedCache,
    ILogger<AccountTargetCooldownStore> logger) : IAccountTargetCooldownStore
{
    private const string KeyPrefix = "auth:cooldown:account-target";

    public async Task<bool> TryAcquireAsync(
        string flow,
        string normalizedIdentity,
        int cooldownSeconds,
        CancellationToken cancellationToken)
    {
        if (cooldownSeconds <= 0)
        {
            return true;
        }

        var cacheKey = BuildCacheKey(flow, normalizedIdentity);

        try
        {
            var existing = await distributedCache.GetStringAsync(cacheKey, cancellationToken);
            if (!string.IsNullOrWhiteSpace(existing))
            {
                return false;
            }
        }
        catch (Exception exception)
        {
            logger.LogError(
                exception,
                "Account target cooldown cache get failed for flow {Flow}. Blocking mail enqueue to avoid spam amplification.",
                flow);
            return false;
        }

        try
        {
            await distributedCache.SetStringAsync(
                cacheKey,
                "1",
                new DistributedCacheEntryOptions
                {
                    AbsoluteExpirationRelativeToNow = TimeSpan.FromSeconds(cooldownSeconds)
                },
                cancellationToken);
        }
        catch (Exception exception)
        {
            logger.LogError(
                exception,
                "Account target cooldown cache set failed for flow {Flow}. Blocking mail enqueue to avoid spam amplification.",
                flow);
            return false;
        }

        return true;
    }

    private static string BuildCacheKey(string flow, string normalizedIdentity)
    {
        var hash = SHA256.HashData(Encoding.UTF8.GetBytes(normalizedIdentity));
        var identityHash = Convert.ToHexString(hash[..12]).ToLowerInvariant();
        return $"{KeyPrefix}:{flow}:{identityHash}";
    }
}
