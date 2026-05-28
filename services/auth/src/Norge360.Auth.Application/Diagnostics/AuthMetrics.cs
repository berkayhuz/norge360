// <copyright file="AuthMetrics.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using System.Diagnostics.Metrics;

namespace Norge360.Auth.Application.Diagnostics;

public static class AuthMetrics
{
    public static readonly Meter Meter = new("Norge360.Auth");

    public static readonly Counter<long> AuthSucceeded = Meter.CreateCounter<long>(
        "auth.succeeded",
        description: "Number of successful register or login flows.");

    public static readonly Counter<long> AuthFailed = Meter.CreateCounter<long>(
        "auth.failed",
        description: "Number of failed authentication attempts.");

    public static readonly Counter<long> RefreshSucceeded = Meter.CreateCounter<long>(
        "auth.refresh.succeeded",
        description: "Number of successful refresh token operations.");

    public static readonly Counter<long> RefreshFailed = Meter.CreateCounter<long>(
        "auth.refresh.failed",
        description: "Number of failed refresh token operations.");

    public static readonly Counter<long> RefreshReuseDetected = Meter.CreateCounter<long>(
        "auth.refresh.reuse_detected",
        description: "Number of refresh token reuse detections.");

    public static readonly Counter<long> TrustedGatewayRejected = Meter.CreateCounter<long>(
        "auth.trusted_gateway.rejected",
        description: "Number of requests rejected by trusted gateway validation.");

    public static readonly Counter<long> RateLimitRejected = Meter.CreateCounter<long>(
        "auth.rate_limit.rejected",
        description: "Number of requests rejected by auth rate limiting.");

    public static readonly Counter<long> TokenStateCacheHit = Meter.CreateCounter<long>(
        "auth.token_state.cache.hit",
        description: "Number of token state cache hits.");

    public static readonly Counter<long> TokenStateCacheMiss = Meter.CreateCounter<long>(
        "auth.token_state.cache.miss",
        description: "Number of token state cache misses.");

    public static readonly Counter<long> SessionStateCacheHit = Meter.CreateCounter<long>(
        "auth.session_state.cache.hit",
        description: "Number of session state cache hits.");

    public static readonly Counter<long> SessionStateCacheMiss = Meter.CreateCounter<long>(
        "auth.session_state.cache.miss",
        description: "Number of session state cache misses.");
}
