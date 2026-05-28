// <copyright file="Norge360AcceptLanguageRequestCultureProvider.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Localization;
using Norge360.Localization;

namespace Norge360.AspNetCore.Localization.Providers;

public sealed class Norge360AcceptLanguageRequestCultureProvider : RequestCultureProvider
{
    public override Task<ProviderCultureResult?> DetermineProviderCultureResult(HttpContext httpContext)
    {
        ArgumentNullException.ThrowIfNull(httpContext);
        var header = httpContext.Request.Headers.AcceptLanguage.ToString();
        if (string.IsNullOrWhiteSpace(header))
        {
            return Task.FromResult<ProviderCultureResult?>(null);
        }

        var span = header.AsSpan();
        var start = 0;

        for (var i = 0; i <= span.Length; i++)
        {
            if (i < span.Length && span[i] != ',')
            {
                continue;
            }

            var segment = span.Slice(start, i - start).Trim();
            start = i + 1;
            if (segment.IsEmpty)
            {
                continue;
            }

            var qualitySeparator = segment.IndexOf(';');
            if (qualitySeparator >= 0)
            {
                segment = segment[..qualitySeparator].Trim();
            }

            if (segment.IsEmpty)
            {
                continue;
            }

            var culture = Norge360Cultures.Normalize(segment.ToString());
            if (culture is not null)
            {
                return Task.FromResult<ProviderCultureResult?>(new ProviderCultureResult(culture, culture));
            }
        }

        return Task.FromResult<ProviderCultureResult?>(null);
    }
}
