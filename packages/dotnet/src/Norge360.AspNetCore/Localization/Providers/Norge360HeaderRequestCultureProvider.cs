// <copyright file="Norge360HeaderRequestCultureProvider.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Localization;
using Norge360.Localization;

namespace Norge360.AspNetCore.Localization.Providers;

public sealed class Norge360HeaderRequestCultureProvider : RequestCultureProvider
{
    public override Task<ProviderCultureResult?> DetermineProviderCultureResult(HttpContext httpContext)
    {
        ArgumentNullException.ThrowIfNull(httpContext);
        var culture = httpContext.Request.Headers.TryGetValue(Norge360Cultures.HeaderName, out var value)
            ? Norge360Cultures.Normalize(value.FirstOrDefault())
            : null;

        return Task.FromResult(culture is null ? null : new ProviderCultureResult(culture, culture));
    }
}
