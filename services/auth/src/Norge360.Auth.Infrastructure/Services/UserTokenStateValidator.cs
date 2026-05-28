// <copyright file="UserTokenStateValidator.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using System.Text.Json;
using Microsoft.Extensions.Caching.Distributed;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using Norge360.Auth.Application.Abstractions;
using Norge360.Auth.Application.Diagnostics;
using Norge360.Auth.Application.Options;

namespace Norge360.Auth.Infrastructure.Services;

public sealed class UserTokenStateValidator(
    IUserRepository userRepository,
    IDistributedCache distributedCache,
    IOptions<TokenValidationCacheOptions> options,
    ILogger<UserTokenStateValidator> logger) : IUserTokenStateValidator
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);

    public async Task<bool> IsValidAsync(Guid tenantId, Guid userId, int tokenVersion, CancellationToken cancellationToken)
    {
        var value = options.Value;
        var cacheKey = BuildCacheKey(value.KeyPrefix, tenantId, userId);

        if (value.EnableCache)
        {
            try
            {
                var cachedPayload = await distributedCache.GetStringAsync(cacheKey, cancellationToken);
                if (!string.IsNullOrWhiteSpace(cachedPayload))
                {
                    AuthMetrics.TokenStateCacheHit.Add(1);
                    var cachedState = JsonSerializer.Deserialize<CachedUserTokenState>(cachedPayload, JsonOptions);
                    if (cachedState is not null)
                    {
                        return cachedState.Exists &&
                               cachedState.IsActive &&
                               cachedState.TokenVersion == tokenVersion;
                    }
                }

                AuthMetrics.TokenStateCacheMiss.Add(1);
            }
            catch (Exception exception)
            {
                logger.LogWarning(
                    exception,
                    "Token validation cache get failed for tenant {TenantId} user {UserId}. Falling back to repository.",
                    tenantId,
                    userId);
            }
        }

        var tokenState = await userRepository.GetActiveTokenStateAsync(tenantId, userId, cancellationToken);

        var currentState = tokenState is null
            ? new CachedUserTokenState(false, false, -1)
            : new CachedUserTokenState(true, true, tokenState.TokenVersion);

        if (value.EnableCache)
        {
            var payload = JsonSerializer.Serialize(currentState, JsonOptions);
            var ttlSeconds = currentState.Exists && currentState.IsActive
                ? value.AbsoluteExpirationSeconds
                : value.NegativeAbsoluteExpirationSeconds;

            try
            {
                await distributedCache.SetStringAsync(
                    cacheKey,
                    payload,
                    new DistributedCacheEntryOptions
                    {
                        AbsoluteExpirationRelativeToNow = TimeSpan.FromSeconds(ttlSeconds)
                    },
                    cancellationToken);
            }
            catch (Exception exception)
            {
                logger.LogWarning(
                    exception,
                    "Token validation cache set failed for tenant {TenantId} user {UserId}.",
                    tenantId,
                    userId);
            }
        }

        return currentState.Exists &&
               currentState.IsActive &&
               currentState.TokenVersion == tokenVersion;
    }

    public void Evict(Guid tenantId, Guid userId)
    {
        var value = options.Value;
        if (!value.EnableCache)
        {
            return;
        }

        try
        {
            distributedCache.Remove(BuildCacheKey(value.KeyPrefix, tenantId, userId));
        }
        catch (Exception exception)
        {
            logger.LogError(
                exception,
                "Token validation cache evict failed for tenant {TenantId} user {UserId}.",
                tenantId,
                userId);
        }
    }

    private static string BuildCacheKey(string prefix, Guid tenantId, Guid userId) =>
        $"{prefix}:{tenantId:N}:{userId:N}";

    private sealed record CachedUserTokenState(bool Exists, bool IsActive, int TokenVersion);
}
