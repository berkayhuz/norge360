// <copyright file="Norge360Cultures.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using System.Collections.Frozen;
using System.Globalization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Localization;

namespace Norge360.Localization;

public static class Norge360Cultures
{
    public const string DefaultCulture = "en-US";
    public const string TurkishCulture = "tr-TR";
    public const string EnglishCulture = "en-US";
    public const string CookieName = "nm_culture";
    public const string HeaderName = "X-Norge360-Culture";

    public static readonly IReadOnlyList<string> SupportedCultureNames = [EnglishCulture, TurkishCulture];
    private static readonly FrozenDictionary<string, string> CultureNameLookup = BuildCultureNameLookup();

    public static bool IsSupportedCulture(string? culture)
        => Normalize(culture) is not null;

    public static string NormalizeOrDefault(string? culture)
        => Normalize(culture) ?? DefaultCulture;

    public static string? Normalize(string? culture)
    {
        if (string.IsNullOrWhiteSpace(culture))
        {
            return null;
        }

        var valueSpan = culture.AsSpan().Trim();
        if (valueSpan.IsEmpty)
        {
            return null;
        }

        if (valueSpan.Equals("tr", StringComparison.OrdinalIgnoreCase))
        {
            return TurkishCulture;
        }

        if (valueSpan.Equals("en", StringComparison.OrdinalIgnoreCase))
        {
            return EnglishCulture;
        }

        if (valueSpan.Equals(TurkishCulture, StringComparison.OrdinalIgnoreCase) ||
            valueSpan.Equals("tr_TR", StringComparison.OrdinalIgnoreCase))
        {
            return TurkishCulture;
        }

        if (valueSpan.Equals(EnglishCulture, StringComparison.OrdinalIgnoreCase) ||
            valueSpan.Equals("en_US", StringComparison.OrdinalIgnoreCase))
        {
            return EnglishCulture;
        }

        var value = valueSpan.IndexOf('_') >= 0
            ? valueSpan.ToString().Replace('_', '-')
            : valueSpan.ToString();

        return CultureNameLookup.TryGetValue(value, out var normalized)
            ? normalized
            : null;
    }

    public static void AppendCultureCookie(HttpResponse response, string? culture, string? domain = null)
    {
        var normalized = NormalizeOrDefault(culture);
        response.Cookies.Append(
            CookieName,
            normalized,
            new CookieOptions
            {
                Domain = string.IsNullOrWhiteSpace(domain) ? null : domain,
                Expires = DateTimeOffset.UtcNow.AddYears(1),
                HttpOnly = true,
                IsEssential = true,
                SameSite = SameSiteMode.Lax,
                Secure = true
            });
    }

    public static RequestCulture ToRequestCulture(string? culture)
    {
        var normalized = NormalizeOrDefault(culture);
        return new RequestCulture(normalized, normalized);
    }

    private static FrozenDictionary<string, string> BuildCultureNameLookup()
    {
        var cultureMap = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);

        foreach (var culture in CultureInfo.GetCultures(CultureTypes.AllCultures))
        {
            if (string.IsNullOrWhiteSpace(culture.Name))
            {
                continue;
            }

            cultureMap[culture.Name] = culture.Name;
        }

        return cultureMap.ToFrozenDictionary(StringComparer.OrdinalIgnoreCase);
    }
}
