// <copyright file="IdempotencyState.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

namespace Norge360.Idempotency;

public sealed record IdempotencyState(
    IdempotencyStatus Status,
    string RequestHash,
    string ResponseJson)
{
    public static IdempotencyState InProgress(string requestHash)
        => new(IdempotencyStatus.InProgress, requestHash, string.Empty);

    public static IdempotencyState Completed(string requestHash, string responseJson)
        => new(IdempotencyStatus.Completed, requestHash, responseJson);
}
