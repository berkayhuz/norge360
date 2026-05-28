// <copyright file="MediaUrlBuilder.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using Microsoft.Extensions.Options;
using Norge360.Media.Abstractions;
using Norge360.Media.Options;

namespace Norge360.Media.Urls;

public sealed class MediaUrlBuilder(IOptions<MediaOptions> options) : IMediaUrlBuilder
{
    public string BuildPublicUrl(string key)
    {
        var baseUrl = options.Value.PublicBaseUrl?.TrimEnd('/') ?? string.Empty;
        var safeKey = key.TrimStart('/');
        return $"{baseUrl}/{safeKey}";
    }
}
