// <copyright file="AuthVerificationToken.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using Norge360.Entities;

namespace Norge360.Auth.Domain.Entities;

public sealed class AuthVerificationToken : AuditableEntity
{
    public Guid UserId { get; set; }
    public string Purpose { get; set; } = null!;
    public string TokenHash { get; set; } = null!;
    public string? Target { get; set; }
    public DateTime ExpiresAtUtc { get; set; }
    public DateTime? ConsumedAtUtc { get; set; }
    public string? ConsumedByIpAddress { get; set; }
    public int Attempts { get; set; }
    public bool IsConsumed => ConsumedAtUtc.HasValue;
    public bool IsExpired(DateTime utcNow) => utcNow >= ExpiresAtUtc;
    public void Consume(DateTime utcNow, string? ipAddress)
    {
        ConsumedAtUtc = utcNow;
        ConsumedByIpAddress = ipAddress;
    }
}
