// <copyright file="TrustedGatewayValidationResult.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

namespace Norge360.AspNetCore.TrustedGateway.Models;

public sealed record TrustedGatewayValidationResult(bool Succeeded, TrustedGatewayFailureReason FailureReason, string? ErrorCode = null)
{
    public static TrustedGatewayValidationResult Success() => new(true, TrustedGatewayFailureReason.None);

    public static TrustedGatewayValidationResult Fail(TrustedGatewayFailureReason reason, string code) => new(false, reason, code);
}
