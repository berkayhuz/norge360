// <copyright file="IAccessTokenFactory.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using Norge360.Auth.Application.Descriptors;
using Norge360.Auth.Domain.Entities;

namespace Norge360.Auth.Application.Abstractions;

public interface IAccessTokenFactory
{
    AccessTokenDescriptor Create(User user, Guid tenantId, Guid sessionId);
    AccessTokenDescriptor Create(
        Guid userId,
        string userName,
        string email,
        int tokenVersion,
        IReadOnlyCollection<string> roles,
        IReadOnlyCollection<string> permissions,
        Guid tenantId,
        Guid sessionId,
        DateTimeOffset? authenticatedAt = null,
        IReadOnlyCollection<string>? authenticationMethods = null);
}
