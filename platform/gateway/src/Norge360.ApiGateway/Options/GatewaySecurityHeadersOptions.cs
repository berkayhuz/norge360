// <copyright file="GatewaySecurityHeadersOptions.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using System.ComponentModel.DataAnnotations;

namespace Norge360.ApiGateway.Options;

public sealed class GatewaySecurityHeadersOptions
{
    public const string SectionName = "Security:Headers";

    [Required]
    public string ContentSecurityPolicy { get; set; } = "default-src 'self'; frame-ancestors 'none'; base-uri 'self'; object-src 'none';";

    [Required]
    public string ReferrerPolicy { get; set; } = "strict-origin-when-cross-origin";

    [Required]
    public string PermissionsPolicy { get; set; } = "camera=(), geolocation=(), microphone=()";

    public bool EnableHsts { get; set; } = true;

    [Range(300, 31536000)]
    public int HstsMaxAgeSeconds { get; set; } = 31536000;

    public bool PreloadHsts { get; set; } = true;

    public bool IncludeSubDomains { get; set; } = true;
}
