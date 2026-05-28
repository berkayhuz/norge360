// <copyright file="SecurityHeadersMiddleware.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using Microsoft.Extensions.Options;
using Norge360.ApiGateway.Options;
using Norge360.AspNetCore.Security;

namespace Norge360.ApiGateway.Middlewares;

public sealed class SecurityHeadersMiddleware(RequestDelegate next, IOptions<GatewaySecurityHeadersOptions> options)
{
    public async Task InvokeAsync(HttpContext context)
    {
        var value = options.Value;
        SecuritySupport.ApplySecurityHeaders(
            context,
            new SecurityHeadersValues(
                value.ContentSecurityPolicy,
                value.ReferrerPolicy,
                value.PermissionsPolicy,
                value.EnableHsts,
                value.HstsMaxAgeSeconds,
                value.PreloadHsts,
                value.IncludeSubDomains,
                DisableResponseCaching: false));

        await next(context);
    }
}
