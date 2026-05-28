// <copyright file="UserMfaRecoveryCode.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using Norge360.Entities;

namespace Norge360.Auth.Domain.Entities;

public sealed class UserMfaRecoveryCode : AuditableEntity
{
    public Guid UserId { get; set; }
    public string CodeHash { get; set; } = null!;
    public DateTime? ConsumedAtUtc { get; set; }
    public string? ConsumedByIpAddress { get; set; }
    public User? User { get; set; }
    public bool IsConsumed => ConsumedAtUtc.HasValue;
    public void Consume(DateTime utcNow, string? ipAddress)
    {
        ConsumedAtUtc = utcNow;
        ConsumedByIpAddress = ipAddress;
        UpdatedAt = utcNow;
    }
}
