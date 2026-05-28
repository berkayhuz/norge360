// <copyright file="TenantResolutionOptions.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

namespace Norge360.Auth.Application.Options;

public sealed class TenantResolutionOptions
{
    public const string SectionName = "Security:TenantResolution";

    public bool RequireResolvedTenant { get; set; }

    public bool AllowBodyFallback { get; set; } = true;

    public string HeaderName { get; set; } = "X-Tenant-Id";

    public string SlugHeaderName { get; set; } = "X-Tenant-Slug";

    public string[] TrustedHostSuffixes { get; set; } = [];

    public string[] TenantOptionalPathPrefixes { get; set; } = ["/api/auth/register", "/api/auth/session-status"];
}
