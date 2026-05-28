// <copyright file="ITenantInvitationRepository.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using Norge360.Auth.Domain.Entities;

namespace Norge360.Auth.Application.Abstractions;

public interface ITenantInvitationRepository
{
    Task<TenantInvitation?> GetPendingByTokenHashAsync(Guid tenantId, string tokenHash, DateTime utcNow, CancellationToken cancellationToken);
    Task<TenantInvitation?> GetByIdAsync(Guid tenantId, Guid invitationId, CancellationToken cancellationToken);
    Task<IReadOnlyCollection<TenantInvitation>> ListForTenantAsync(Guid tenantId, CancellationToken cancellationToken);
    Task<bool> HasPendingInviteForEmailAsync(Guid tenantId, string normalizedEmail, DateTime utcNow, CancellationToken cancellationToken);
    Task AddAsync(TenantInvitation invitation, CancellationToken cancellationToken);
}
