// <copyright file="Tenant.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

namespace Norge360.Auth.Domain.Entities;

public sealed class Tenant
{
    public Guid Id { get; set; }
    public string Name { get; set; } = null!;
    public string Slug { get; set; } = null!;
    public bool IsActive { get; set; } = true;
    public DateTime CreatedAt { get; set; }
    public DateTime? UpdatedAt { get; set; }
    public string? CreatedBy { get; set; }
    public string? UpdatedBy { get; set; }
    public ICollection<User> Users { get; set; } = [];
    public ICollection<UserTenantMembership> Memberships { get; set; } = [];
    public ICollection<UserSession> Sessions { get; set; } = [];
    public ICollection<AuthAuditEvent> AuditEvents { get; set; } = [];
    public ICollection<TenantInvitation> Invitations { get; set; } = [];
}
