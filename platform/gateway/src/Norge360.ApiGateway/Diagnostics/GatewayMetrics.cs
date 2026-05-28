// <copyright file="GatewayMetrics.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using System.Diagnostics.Metrics;

namespace Norge360.ApiGateway.Diagnostics;

public static class GatewayMetrics
{
    public static readonly Meter Meter = new("Norge360.ApiGateway");

    public static readonly Counter<long> RateLimitRejected = Meter.CreateCounter<long>(
        "gateway.rate_limit.rejected",
        description: "Number of requests rejected by gateway rate limiting.");

    public static readonly Counter<long> TrustedGatewaySigned = Meter.CreateCounter<long>(
        "gateway.trusted_gateway.signed",
        description: "Number of upstream requests signed by the gateway.");

    public static readonly Counter<long> TrustedGatewaySigningFailed = Meter.CreateCounter<long>(
        "gateway.trusted_gateway.signing_failed",
        description: "Number of upstream requests the gateway failed to sign.");
}
