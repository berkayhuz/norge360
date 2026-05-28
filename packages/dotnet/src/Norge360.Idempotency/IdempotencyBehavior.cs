// <copyright file="IdempotencyBehavior.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using MediatR;
using Norge360.CurrentUser;
using Norge360.Exceptions;

namespace Norge360.Idempotency;

public sealed class IdempotencyBehavior<TRequest, TResponse>(
    IIdempotencyStateStore stateStore,
    ICurrentUserService currentUserService)
    : IPipelineBehavior<TRequest, TResponse>
    where TRequest : notnull
{
    private static readonly JsonSerializerOptions SerializerOptions = new(JsonSerializerDefaults.Web);

    public async Task<TResponse> Handle(TRequest request, RequestHandlerDelegate<TResponse> next, CancellationToken cancellationToken)
    {
        if (request is not IIdempotentCommand idempotentCommand ||
            string.IsNullOrWhiteSpace(idempotentCommand.IdempotencyKey))
        {
            return await next(cancellationToken);
        }

        currentUserService.EnsureAuthenticated();
        var tenantId = currentUserService.EnsureTenant();
        var requestHash = ComputeHash(request);
        var cacheKey = $"crm:idempotency:{tenantId:N}:{typeof(TRequest).FullName}:{idempotentCommand.IdempotencyKey}";
        var existing = await stateStore.GetAsync(cacheKey, cancellationToken);
        if (existing is not null)
        {
            return HandleExistingState(existing, requestHash);
        }

        if (!await stateStore.TryMarkInProgressAsync(cacheKey, requestHash, TimeSpan.FromMinutes(30), cancellationToken))
        {
            existing = await stateStore.GetAsync(cacheKey, cancellationToken);
            if (existing is not null)
            {
                return HandleExistingState(existing, requestHash);
            }

            throw new ConflictAppException("An identical idempotent request is already being processed.");
        }

        try
        {
            var response = await next(cancellationToken);
            await stateStore.MarkCompletedAsync(
                cacheKey,
                requestHash,
                JsonSerializer.Serialize(response, SerializerOptions),
                TimeSpan.FromHours(24),
                cancellationToken);

            return response;
        }
        catch
        {
            await stateStore.RemoveAsync(cacheKey, cancellationToken);
            throw;
        }
    }

    private static TResponse HandleExistingState(IdempotencyState existing, string requestHash)
    {
        if (!string.Equals(existing.RequestHash, requestHash, StringComparison.Ordinal))
        {
            throw new ConflictAppException("Idempotency key was already used with a different request payload.");
        }

        if (existing.Status == IdempotencyStatus.Completed)
        {
            return JsonSerializer.Deserialize<TResponse>(existing.ResponseJson, SerializerOptions)
                ?? throw new ConflictAppException("Stored idempotent response could not be deserialized.");
        }

        throw new ConflictAppException("An identical idempotent request is already being processed.");
    }

    private static string ComputeHash(TRequest request)
    {
        var payload = JsonSerializer.Serialize(request, SerializerOptions);
        var hash = SHA256.HashData(Encoding.UTF8.GetBytes(payload));
        return Convert.ToHexString(hash);
    }
}
