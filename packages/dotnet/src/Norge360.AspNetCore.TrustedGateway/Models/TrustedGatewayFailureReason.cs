// <copyright file="TrustedGatewayFailureReason.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

namespace Norge360.AspNetCore.TrustedGateway.Models;

public enum TrustedGatewayFailureReason
{
    None = 0,
    MissingHeaders,
    InvalidSource,
    InvalidKey,
    InvalidTimestamp,
    TimestampSkewExceeded,
    InvalidRemoteAddress,
    InvalidContentHash,
    InvalidSignature,
    ReplayDetected
}
