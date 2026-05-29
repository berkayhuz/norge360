// <copyright file="IAccountTargetCooldownStore.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

namespace Norge360.Auth.Application.Abstractions;

public interface IAccountTargetCooldownStore
{
    Task<bool> TryAcquireAsync(
        string flow,
        string normalizedIdentity,
        int cooldownSeconds,
        CancellationToken cancellationToken);
}
