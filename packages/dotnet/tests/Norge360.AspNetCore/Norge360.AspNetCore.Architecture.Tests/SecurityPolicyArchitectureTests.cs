// <copyright file="SecurityPolicyArchitectureTests.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using Microsoft.AspNetCore.Http;
using Norge360.AspNetCore.Security;

namespace Norge360.AspNetCore.Architecture.Tests;

public class SecurityPolicyArchitectureTests
{
    [Fact]
    public async Task ApplySecurityHeaders_should_emit_secure_headers_for_https_requests()
    {
        var context = new DefaultHttpContext();
        context.Request.Scheme = Uri.UriSchemeHttps;

        var values = new SecurityHeadersValues(
            ContentSecurityPolicy: "default-src 'self'",
            ReferrerPolicy: "strict-origin-when-cross-origin",
            PermissionsPolicy: "geolocation=()",
            EnableHsts: true,
            HstsMaxAgeSeconds: 31536000,
            PreloadHsts: true,
            IncludeSubDomains: true,
            DisableResponseCaching: true);

        SecuritySupport.ApplySecurityHeaders(context, values);
        await context.Response.StartAsync();

        Assert.Equal("nosniff", context.Response.Headers.XContentTypeOptions.ToString());
        Assert.Equal("DENY", context.Response.Headers.XFrameOptions.ToString());
        Assert.Equal(values.ContentSecurityPolicy, context.Response.Headers.ContentSecurityPolicy.ToString());
        Assert.Equal(values.ReferrerPolicy, context.Response.Headers["Referrer-Policy"].ToString());
        Assert.Equal(values.PermissionsPolicy, context.Response.Headers["Permissions-Policy"].ToString());
        Assert.Equal("none", context.Response.Headers["X-Permitted-Cross-Domain-Policies"].ToString());
        Assert.Equal("same-origin", context.Response.Headers["Cross-Origin-Opener-Policy"].ToString());
        Assert.Equal("no-store", context.Response.Headers.CacheControl.ToString());
        Assert.Equal("no-cache", context.Response.Headers.Pragma.ToString());
        Assert.Equal(
            "max-age=31536000; includeSubDomains; preload",
            context.Response.Headers.StrictTransportSecurity.ToString());
    }

    [Fact]
    public async Task ApplySecurityHeaders_should_not_emit_hsts_for_http_requests()
    {
        var context = new DefaultHttpContext();
        context.Request.Scheme = Uri.UriSchemeHttp;

        var values = new SecurityHeadersValues(
            ContentSecurityPolicy: "default-src 'self'",
            ReferrerPolicy: "strict-origin-when-cross-origin",
            PermissionsPolicy: "geolocation=()",
            EnableHsts: true,
            HstsMaxAgeSeconds: 31536000,
            PreloadHsts: true,
            IncludeSubDomains: true,
            DisableResponseCaching: false);

        SecuritySupport.ApplySecurityHeaders(context, values);
        await context.Response.StartAsync();

        Assert.False(
            context.Response.Headers.ContainsKey("Strict-Transport-Security"),
            "HSTS must only be emitted for HTTPS requests to avoid policy misuse in non-TLS contexts.");
    }
}
