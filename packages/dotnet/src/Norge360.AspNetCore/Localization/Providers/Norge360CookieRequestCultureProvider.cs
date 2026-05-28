// <copyright file="Norge360CookieRequestCultureProvider.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Localization;
using Norge360.Localization;

namespace Norge360.AspNetCore.Localization.Providers;

public sealed class Norge360CookieRequestCultureProvider : RequestCultureProvider
{
    public override Task<ProviderCultureResult?> DetermineProviderCultureResult(HttpContext httpContext)
    {
        ArgumentNullException.ThrowIfNull(httpContext);

        if (!httpContext.Request.Cookies.TryGetValue(Norge360Cultures.CookieName, out var cookieValue))
        {
            return Task.FromResult<ProviderCultureResult?>(null);
        }

        var culture = Norge360Cultures.Normalize(cookieValue);
        if (culture is null && cookieValue.Contains("c=", StringComparison.Ordinal))
        {
            culture = TryExtractCultureFromFrameworkCookieFormat(cookieValue);
            if (culture is null)
            {
                var parsed = CookieRequestCultureProvider.ParseCookieValue(cookieValue);
                culture = Norge360Cultures.Normalize(parsed?.Cultures.FirstOrDefault().Value);
            }
        }

        return Task.FromResult(culture is null ? null : new ProviderCultureResult(culture, culture));
    }

    private static string? TryExtractCultureFromFrameworkCookieFormat(string cookieValue)
    {
        var span = cookieValue.AsSpan().Trim();
        if (!span.StartsWith("c=", StringComparison.Ordinal))
        {
            return null;
        }

        span = span[2..];
        var separatorIndex = span.IndexOf('|');
        var cultureSpan = separatorIndex >= 0 ? span[..separatorIndex] : span;
        cultureSpan = cultureSpan.Trim();
        if (cultureSpan.IsEmpty)
        {
            return null;
        }

        return Norge360Cultures.Normalize(cultureSpan.ToString());
    }
}
