// <copyright file="TrustedDeviceIdentityResponse.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

namespace Norge360.Auth.Contracts.Internal;

public sealed record TrustedDeviceIdentityResponse(
    Guid Id,
    bool IsCurrent,
    string? DeviceName,
    string? IpAddress,
    string? UserAgent,
    DateTimeOffset TrustedAt,
    DateTimeOffset? LastSeenAt,
    bool IsRevoked);
