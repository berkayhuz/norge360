// <copyright file="UserSession.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using Norge360.Entities;

namespace Norge360.Auth.Domain.Entities;

public sealed class UserSession : AuditableEntity
{
    public Guid UserId { get; set; }
    public bool IsPersistent { get; set; }
    public Guid RefreshTokenFamilyId { get; set; }
    public string RefreshTokenHash { get; set; } = null!;
    public DateTime RefreshTokenExpiresAt { get; set; }
    public DateTime? LastSeenAt { get; set; }
    public DateTime? LastRefreshedAt { get; set; }
    public DateTime? RefreshTokenReplacedAt { get; set; }
    public DateTime? RefreshTokenReuseDetectedAt { get; set; }
    public DateTime? RevokedAt { get; set; }
    public string? RevokedReason { get; set; }
    public string? IpAddress { get; set; }
    public string? UserAgent { get; set; }
    public User? User { get; set; }
    public bool IsRevoked => RevokedAt.HasValue;
    public void Revoke(DateTime utcNow, string reason)
    {
        RevokedAt = utcNow;
        RevokedReason = reason;
        UpdatedAt = utcNow;
    }
    public void MarkRefreshRotated(DateTime utcNow)
    {
        LastRefreshedAt = utcNow;
        RefreshTokenReplacedAt = utcNow;
        LastSeenAt = utcNow;
        UpdatedAt = utcNow;
    }
    public void MarkRefreshTokenReuse(DateTime utcNow, string reason)
    {
        RefreshTokenReuseDetectedAt = utcNow;
        Revoke(utcNow, reason);
    }
}
