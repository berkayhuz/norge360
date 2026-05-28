// <copyright file="UserTenantMembership.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using Norge360.Entities;

namespace Norge360.Auth.Domain.Entities;

public sealed class UserTenantMembership : AuditableEntity
{
    public Guid UserId { get; set; }
    public string Roles { get; set; } = "tenant-user";
    public string Permissions { get; set; } = "session:self,profile:self";
    public DateTime? LastRoleChangeAt { get; set; }
    public Guid? LastRoleChangedByUserId { get; set; }
    public User? User { get; set; }
    public IReadOnlyCollection<string> GetRoles() =>
        Roles.Split(',', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries)
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToArray();
    public IReadOnlyCollection<string> GetPermissions() =>
        Permissions.Split(',', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries)
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToArray();
}
