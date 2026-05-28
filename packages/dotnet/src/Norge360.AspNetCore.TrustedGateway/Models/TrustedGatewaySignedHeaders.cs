// <copyright file="TrustedGatewaySignedHeaders.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

namespace Norge360.AspNetCore.TrustedGateway.Models;

public sealed record TrustedGatewaySignedHeaders(
    string Signature,
    string Timestamp,
    string KeyId,
    string Source,
    string Nonce,
    string ContentHash,
    string CorrelationId);
