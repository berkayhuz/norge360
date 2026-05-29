// <copyright file="AuthAuditTrailReader.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using Microsoft.EntityFrameworkCore;
using Norge360.Auth.Application.Abstractions;
using Norge360.Auth.Infrastructure.Persistence;

namespace Norge360.Auth.Infrastructure.Services;

public sealed class AuthAuditTrailReader(AuthDbContext dbContext) : IAuthAuditTrailReader
{
    public async Task<DateTimeOffset?> GetLastSecurityEventAtAsync(Guid userId, CancellationToken cancellationToken)
    {
        var createdAt = await dbContext.AuthAuditEvents
            .Where(x => x.UserId == userId && !x.IsDeleted && x.EventType.StartsWith("auth."))
            .OrderByDescending(x => x.CreatedAt)
            .Select(x => (DateTime?)x.CreatedAt)
            .FirstOrDefaultAsync(cancellationToken);

        return createdAt.HasValue ? new DateTimeOffset(DateTime.SpecifyKind(createdAt.Value, DateTimeKind.Utc)) : null;
    }
}
