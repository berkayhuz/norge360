// <copyright file="CookieOriginProtectionMiddleware.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using Microsoft.Extensions.Options;
using Norge360.AspNetCore.ProblemDetails;
using Norge360.Auth.API.Cookies;
using Norge360.Auth.API.Security;
using Norge360.Auth.Application.Options;

namespace Norge360.Auth.API.Middlewares;

public sealed class CookieOriginProtectionMiddleware(
    RequestDelegate next,
    IOptions<ApiCorsOptions> corsOptions,
    IOptions<TokenTransportOptions> tokenTransportOptions,
    AuthCookieService cookieService,
    ILogger<CookieOriginProtectionMiddleware> logger)
{
    private static readonly HashSet<string> SafeMethods = new(StringComparer.OrdinalIgnoreCase)
    {
        HttpMethods.Get,
        HttpMethods.Head,
        HttpMethods.Options,
        HttpMethods.Trace
    };

    private static readonly PathString[] AnonymousAllowedPrefixes =
    [
        new("/health"),
        new("/.well-known"),
        new("/swagger")
    ];

    public async Task InvokeAsync(HttpContext context)
    {
        if (SafeMethods.Contains(context.Request.Method) ||
            AnonymousAllowedPrefixes.Any(prefix => context.Request.Path.StartsWithSegments(prefix)))
        {
            await next(context);
            return;
        }

        var transport = tokenTransportOptions.Value;
        if (string.Equals(transport.Mode, TokenTransportModes.BodyOnly, StringComparison.OrdinalIgnoreCase))
        {
            await next(context);
            return;
        }

        var carriesAuthCookies =
            context.Request.Cookies.ContainsKey(cookieService.AccessCookieName) ||
            context.Request.Cookies.ContainsKey(cookieService.RefreshCookieName) ||
            context.Request.Cookies.ContainsKey(cookieService.SessionCookieName);

        if (!carriesAuthCookies)
        {
            await next(context);
            return;
        }

        if (!TryResolveRequestOrigin(context.Request, out var requestOrigin) ||
            !IsAllowedOrigin(requestOrigin, corsOptions.Value.AllowedOrigins))
        {
            logger.LogWarning(
                "Cookie-origin protection rejected request for {Path}. Origin={Origin}",
                context.Request.Path,
                requestOrigin?.ToString() ?? "missing");

            await ProblemDetailsSupport.WriteProblemAsync(
                context,
                StatusCodes.Status403Forbidden,
                "Origin validation failed",
                "Cookie-authenticated unsafe requests must originate from an allowed frontend origin.",
                errorCode: "cookie_origin_validation_failed",
                cancellationToken: context.RequestAborted);

            return;
        }

        await next(context);
    }

    private static bool TryResolveRequestOrigin(HttpRequest request, out Uri? origin)
    {
        origin = null;

        var originHeader = request.Headers.Origin.ToString();
        if (!string.IsNullOrWhiteSpace(originHeader) &&
            Uri.TryCreate(originHeader, UriKind.Absolute, out var parsedOrigin))
        {
            origin = parsedOrigin;
            return true;
        }

        var refererHeader = request.Headers.Referer.ToString();
        if (!string.IsNullOrWhiteSpace(refererHeader) &&
            Uri.TryCreate(refererHeader, UriKind.Absolute, out var parsedReferer))
        {
            origin = new Uri(parsedReferer.GetLeftPart(UriPartial.Authority));
            return true;
        }

        return false;
    }

    private static bool IsAllowedOrigin(Uri? requestOrigin, IEnumerable<string> allowedOrigins)
    {
        if (requestOrigin is null)
        {
            return false;
        }

        foreach (var allowedOrigin in allowedOrigins)
        {
            if (!Uri.TryCreate(allowedOrigin, UriKind.Absolute, out var configuredOrigin))
            {
                continue;
            }

            if (Uri.Compare(requestOrigin, configuredOrigin, UriComponents.SchemeAndServer, UriFormat.Unescaped, StringComparison.OrdinalIgnoreCase) == 0)
            {
                return true;
            }
        }

        return false;
    }
}
