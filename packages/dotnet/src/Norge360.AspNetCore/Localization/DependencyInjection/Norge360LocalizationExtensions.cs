// <copyright file="Norge360LocalizationExtensions.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using System.Globalization;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Localization;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Options;
using Norge360.AspNetCore.Localization.Providers;
using Norge360.Localization;

namespace Norge360.AspNetCore.Localization.DependencyInjection;

public static class Norge360LocalizationExtensions
{
    public static IServiceCollection AddNorge360Localization(this IServiceCollection services)
    {
        services.Configure<RequestLocalizationOptions>(options =>
        {
            var supportedCultures = Norge360Cultures.SupportedCultureNames
                .Select(culture => new CultureInfo(culture))
                .ToArray();

            options.DefaultRequestCulture = Norge360Cultures.ToRequestCulture(Norge360Cultures.DefaultCulture);
            options.SupportedCultures = supportedCultures;
            options.SupportedUICultures = supportedCultures;
            options.FallBackToParentCultures = false;
            options.FallBackToParentUICultures = false;
            options.ApplyCurrentCultureToResponseHeaders = true;
            options.RequestCultureProviders =
            [
                new QueryStringRequestCultureProvider(),
                new Norge360HeaderRequestCultureProvider(),
                new Norge360CookieRequestCultureProvider(),
                new Norge360AcceptLanguageRequestCultureProvider()
            ];
        });

        return services;
    }

    public static IApplicationBuilder UseNorge360Localization(this IApplicationBuilder app)
    {
        var options = app.ApplicationServices.GetRequiredService<IOptions<RequestLocalizationOptions>>().Value;
        return app.UseRequestLocalization(options);
    }
}
