// <copyright file="User.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using Norge360.Entities;

namespace Norge360.Auth.Domain.Entities;

public class User : AuditableEntity
{
    public string UserName { get; set; } = null!;
    public string NormalizedUserName { get; set; } = null!;
    public string? Email { get; set; } = null!;
    public string NormalizedEmail { get; set; } = null!;
    public string PasswordHash { get; set; } = null!;
    public string? FirstName { get; set; }
    public string? LastName { get; set; }
    public bool EmailConfirmed { get; set; }
    public DateTime? EmailConfirmedAt { get; set; }
    public string SecurityStamp { get; set; } = Guid.NewGuid().ToString("N");
    public DateTime? PasswordChangedAt { get; set; }
    public bool IsLocked { get; set; }
    public DateTime? LockoutEndAt { get; set; }
    public int AccessFailedCount { get; set; }
    public int TokenVersion { get; set; }
    public DateTime? LastLoginAt { get; set; }
    public bool ForcePasswordChange { get; set; }
    public bool MfaEnabled { get; set; }
    public DateTime? MfaEnabledAt { get; set; }
    public string? AuthenticatorKeyProtected { get; set; }
    public DateTime? AuthenticatorKeyCreatedAt { get; set; }
    public DateTime? AuthenticatorKeyConfirmedAt { get; set; }
    public DateTime? RecoveryCodesGeneratedAt { get; set; }
    public string Roles { get; set; } = "user";
    public string Permissions { get; set; } = "session:self,profile:self";
    public ICollection<UserSession> Sessions { get; set; } = [];
    public ICollection<AuthAuditEvent> AuditEvents { get; set; } = [];
    public ICollection<AuthVerificationToken> VerificationTokens { get; set; } = [];
    public ICollection<UserMfaRecoveryCode> RecoveryCodes { get; set; } = [];
    public ICollection<TrustedDevice> TrustedDevices { get; set; } = [];
    public IReadOnlyCollection<string> GetRoles() =>
        Roles.Split(',', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries)
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToArray();
    public IReadOnlyCollection<string> GetPermissions() =>
        Permissions.Split(',', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries)
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToArray();
}
