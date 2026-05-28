// <copyright file="UserSessionStateValidator.cs" company="Norge360">
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
using Norge360.Clock;

namespace Norge360.Auth.Infrastructure.Services;

public sealed class UserSessionStateValidator(
    IUserSessionRepository userSessionRepository,
    IAuthSessionService authSessionService,
    IDistributedCache distributedCache,
    IOptions<TokenValidationCacheOptions> options,
    IClock clock,
    ILogger<UserSessionStateValidator> logger) : IUserSessionStateValidator
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);

    public async Task<bool> IsValidAsync(Guid tenantId, Guid userId, Guid sessionId, CancellationToken cancellationToken)
    {
        var value = options.Value;
        var cacheKey = BuildCacheKey(value.KeyPrefix, tenantId, sessionId);

        if (value.EnableCache)
        {
            try
            {
                var cachedPayload = await distributedCache.GetStringAsync(cacheKey, cancellationToken);
                if (!string.IsNullOrWhiteSpace(cachedPayload))
                {
                    AuthMetrics.SessionStateCacheHit.Add(1);
                    var cachedState = JsonSerializer.Deserialize<CachedSessionState>(cachedPayload, JsonOptions);
                    if (cachedState is not null && cachedState.UserId == userId)
                    {
                        return cachedState.IsValid;
                    }
                }

                AuthMetrics.SessionStateCacheMiss.Add(1);
            }
            catch (Exception exception)
            {
                logger.LogWarning(
                    exception,
                    "Session validation cache get failed for tenant {TenantId} session {SessionId}. Falling back to repository.",
                    tenantId,
                    sessionId);
            }
        }

        var session = await userSessionRepository.GetAsync(tenantId, sessionId, cancellationToken);
        var isValid = session is not null &&
                      session.UserId == userId &&
                      !session.IsRevoked &&
                      !authSessionService.IsExpired(session, clock.UtcDateTime);

        if (value.EnableCache)
        {
            var ttlSeconds = isValid
                ? value.AbsoluteExpirationSeconds
                : value.NegativeAbsoluteExpirationSeconds;

            try
            {
                await distributedCache.SetStringAsync(
                    cacheKey,
                    JsonSerializer.Serialize(new CachedSessionState(userId, isValid), JsonOptions),
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
                    "Session validation cache set failed for tenant {TenantId} session {SessionId}.",
                    tenantId,
                    sessionId);
            }
        }

        return isValid;
    }

    public void Evict(Guid tenantId, Guid sessionId)
    {
        var value = options.Value;
        if (!value.EnableCache)
        {
            return;
        }

        try
        {
            distributedCache.Remove(BuildCacheKey(value.KeyPrefix, tenantId, sessionId));
        }
        catch (Exception exception)
        {
            logger.LogError(
                exception,
                "Session validation cache evict failed for tenant {TenantId} session {SessionId}.",
                tenantId,
                sessionId);
        }
    }

    private static string BuildCacheKey(string prefix, Guid tenantId, Guid sessionId) =>
        $"{prefix}:session:{tenantId:N}:{sessionId:N}";

    private sealed record CachedSessionState(Guid UserId, bool IsValid);
}
