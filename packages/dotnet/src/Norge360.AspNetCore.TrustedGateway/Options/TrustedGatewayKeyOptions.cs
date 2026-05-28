// <copyright file="TrustedGatewayKeyOptions.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

namespace Norge360.AspNetCore.TrustedGateway.Options;

public sealed class TrustedGatewayKeyOptions
{
    public string KeyId { get; set; } = string.Empty;

    public string Secret { get; set; } = string.Empty;

    public bool Enabled { get; set; } = true;

    public bool SignRequests { get; set; } = true;
}
