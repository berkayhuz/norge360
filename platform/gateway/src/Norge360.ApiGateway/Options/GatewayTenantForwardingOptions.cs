// <copyright file="GatewayTenantForwardingOptions.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using System.ComponentModel.DataAnnotations;

namespace Norge360.ApiGateway.Options;

public sealed class GatewayTenantForwardingOptions
{
    public const string SectionName = "Security:TenantForwarding";

    public bool RequireTenant { get; set; } = true;

    public bool AllowStaticTenantIdInProduction { get; set; }

    public Guid StaticTenantId { get; set; }

    public string StaticTenantSlug { get; set; } = string.Empty;

    public string HeaderName { get; set; } = "X-Tenant-Id";

    public string SlugHeaderName { get; set; } = "X-Tenant-Slug";

    public string RouteMetadataTenantIdKey { get; set; } = "TenantId";

    public string RouteMetadataTenantSlugKey { get; set; } = "TenantSlug";

    [MinLength(0)]
    public string[] TrustedHostSuffixes { get; set; } = [];

    public string[] ReservedSubdomains { get; set; } = ["app", "api", "auth", "gateway", "www"];
}
