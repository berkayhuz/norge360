// <copyright file="GatewayForwardedHeadersOptions.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using System.ComponentModel.DataAnnotations;

namespace Norge360.ApiGateway.Options;

public sealed class GatewayForwardedHeadersOptions
{
    public const string SectionName = "Security:ForwardedHeaders";

    [Range(1, 10)]
    public int ForwardLimit { get; set; } = 2;

    public string[] KnownProxies { get; set; } = [];

    public string[] KnownNetworks { get; set; } = [];
}
