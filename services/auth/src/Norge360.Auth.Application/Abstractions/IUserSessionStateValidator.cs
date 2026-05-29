// <copyright file="IUserSessionStateValidator.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

namespace Norge360.Auth.Application.Abstractions;

public interface IUserSessionStateValidator
{
    Task<bool> IsValidAsync(Guid userId, Guid sessionId, CancellationToken cancellationToken);

    void Evict(Guid sessionId);
}
