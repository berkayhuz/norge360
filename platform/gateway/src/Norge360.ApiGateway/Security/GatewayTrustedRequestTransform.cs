// <copyright file="GatewayTrustedRequestTransform.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using System.Text.RegularExpressions;
using Microsoft.Extensions.Options;
using Norge360.ApiGateway.Diagnostics;
using Norge360.ApiGateway.Options;
using Norge360.AspNetCore.RequestContext;
using Norge360.AspNetCore.TrustedGateway.Abstractions;
using Norge360.AspNetCore.TrustedGateway.Options;
using Norge360.Localization;
using Yarp.ReverseProxy.Transforms;

namespace Norge360.ApiGateway.Security;

public sealed partial class GatewayTrustedRequestTransform(
    ITrustedGatewaySigner signer,
    IOptions<TrustedGatewayOptions> options,
    IOptions<GatewayTenantForwardingOptions> tenantForwardingOptions,
    ILogger<GatewayTrustedRequestTransform> logger)
{
    public const string TenantForwardingMetadataKey = "TenantForwarding";

    private static readonly string[] SpoofableHeaders =
    [
        "X-Powered-By",
        RequestContextSupport.CorrelationIdHeaderName,
        "X-Original-Client-IP",
        "X-Tenant-Id",
        "X-Tenant-Slug",
        Norge360Cultures.HeaderName
    ];

    public void ApplyCommonHeaders(RequestTransformContext context, IReadOnlyDictionary<string, string>? routeMetadata = null)
    {
        var trustedGatewayOptions = options.Value;
        var tenantOptions = tenantForwardingOptions.Value;

        foreach (var header in SpoofableHeaders)
        {
            context.ProxyRequest.Headers.Remove(header);
        }

        context.ProxyRequest.Headers.Remove(trustedGatewayOptions.SignatureHeaderName);
        context.ProxyRequest.Headers.Remove(trustedGatewayOptions.TimestampHeaderName);
        context.ProxyRequest.Headers.Remove(trustedGatewayOptions.KeyIdHeaderName);
        context.ProxyRequest.Headers.Remove(trustedGatewayOptions.SourceHeaderName);
        context.ProxyRequest.Headers.Remove(trustedGatewayOptions.NonceHeaderName);
        context.ProxyRequest.Headers.Remove(trustedGatewayOptions.ContentHashHeaderName);
        context.ProxyRequest.Headers.Remove(tenantOptions.HeaderName);
        context.ProxyRequest.Headers.Remove(tenantOptions.SlugHeaderName);

        var correlationId = RequestContextSupport.GetOrCreateCorrelationId(context.HttpContext);

        context.ProxyRequest.Headers.TryAddWithoutValidation(
            RequestContextSupport.CorrelationIdHeaderName,
            correlationId);

        context.ProxyRequest.Headers.TryAddWithoutValidation(
            "X-Original-Client-IP",
            context.HttpContext.Connection.RemoteIpAddress?.ToString() ?? "unknown");

        if (ShouldForwardTenant(routeMetadata))
        {
            ApplyTenantHeaders(context, tenantOptions);
        }

        context.ProxyRequest.Headers.TryAddWithoutValidation(
            Norge360Cultures.HeaderName,
            ResolveCulture(context.HttpContext.Request));
    }

    private static bool ShouldForwardTenant(IReadOnlyDictionary<string, string>? routeMetadata) =>
        routeMetadata is null ||
        !routeMetadata.TryGetValue(TenantForwardingMetadataKey, out var configured) ||
        !bool.TryParse(configured, out var enabled) ||
        enabled;

    private static string ResolveCulture(HttpRequest request)
    {
        if (request.Cookies.TryGetValue(Norge360Cultures.CookieName, out var cookieCulture))
        {
            return Norge360Cultures.NormalizeOrDefault(cookieCulture);
        }

        if (request.Headers.TryGetValue("Accept-Language", out var acceptLanguage))
        {
            var first = acceptLanguage.ToString()
                .Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
                .FirstOrDefault();

            return Norge360Cultures.NormalizeOrDefault(first?.Split(';')[0]);
        }

        return Norge360Cultures.DefaultCulture;
    }

    public async Task ApplySigningAsync(RequestTransformContext context, CancellationToken cancellationToken)
    {
        var trustedGatewayOptions = options.Value;
        var correlationId = RequestContextSupport.GetOrCreateCorrelationId(context.HttpContext);

        try
        {
            var signedHeaders = await signer.SignAsync(context.HttpContext.Request, correlationId, cancellationToken);

            context.ProxyRequest.Headers.TryAddWithoutValidation(trustedGatewayOptions.SourceHeaderName, signedHeaders.Source);
            context.ProxyRequest.Headers.TryAddWithoutValidation(trustedGatewayOptions.TimestampHeaderName, signedHeaders.Timestamp);
            context.ProxyRequest.Headers.TryAddWithoutValidation(trustedGatewayOptions.KeyIdHeaderName, signedHeaders.KeyId);
            context.ProxyRequest.Headers.TryAddWithoutValidation(trustedGatewayOptions.NonceHeaderName, signedHeaders.Nonce);
            context.ProxyRequest.Headers.TryAddWithoutValidation(trustedGatewayOptions.ContentHashHeaderName, signedHeaders.ContentHash);
            context.ProxyRequest.Headers.TryAddWithoutValidation(trustedGatewayOptions.SignatureHeaderName, signedHeaders.Signature);

            GatewayMetrics.TrustedGatewaySigned.Add(
                1,
                new KeyValuePair<string, object?>("path", context.HttpContext.Request.Path.Value));
        }
        catch (Exception exception)
        {
            GatewayMetrics.TrustedGatewaySigningFailed.Add(
                1,
                new KeyValuePair<string, object?>("path", context.HttpContext.Request.Path.Value));

            logger.LogError(exception, "Failed to sign proxied request for {Path}.", context.HttpContext.Request.Path);
            throw;
        }
    }

    private void ApplyTenantHeaders(RequestTransformContext context, GatewayTenantForwardingOptions tenantOptions)
    {
        if (tenantOptions.StaticTenantId != Guid.Empty)
        {
            context.ProxyRequest.Headers.TryAddWithoutValidation(
                tenantOptions.HeaderName,
                tenantOptions.StaticTenantId.ToString("D"));
            return;
        }

        var configuredSlug = NormalizeSlug(tenantOptions.StaticTenantSlug);
        if (configuredSlug is not null)
        {
            context.ProxyRequest.Headers.TryAddWithoutValidation(tenantOptions.SlugHeaderName, configuredSlug);
            return;
        }

        var hostSlug = ResolveSlugFromHost(context.HttpContext.Request.Host.Host, tenantOptions);
        if (hostSlug is not null)
        {
            context.ProxyRequest.Headers.TryAddWithoutValidation(tenantOptions.SlugHeaderName, hostSlug);
            return;
        }

        if (!tenantOptions.RequireTenant)
        {
            return;
        }

        logger.LogWarning(
            "Tenant forwarding could not resolve a trusted tenant for {Host}{Path}.",
            context.HttpContext.Request.Host.Host,
            context.HttpContext.Request.Path);

        throw new InvalidOperationException("Security:TenantForwarding could not resolve a trusted tenant.");
    }

    private static string? ResolveSlugFromHost(string host, GatewayTenantForwardingOptions options)
    {
        if (string.IsNullOrWhiteSpace(host))
        {
            return null;
        }

        var normalizedHost = host.Trim().TrimEnd('.').ToLowerInvariant();
        foreach (var suffix in options.TrustedHostSuffixes)
        {
            var normalizedSuffix = suffix.Trim().TrimStart('.').TrimEnd('.').ToLowerInvariant();
            if (normalizedHost.Equals(normalizedSuffix, StringComparison.Ordinal))
            {
                continue;
            }

            var suffixWithDot = "." + normalizedSuffix;
            if (!normalizedHost.EndsWith(suffixWithDot, StringComparison.Ordinal))
            {
                continue;
            }

            var subdomain = normalizedHost[..^suffixWithDot.Length];
            if (subdomain.Contains('.', StringComparison.Ordinal))
            {
                continue;
            }

            var slug = NormalizeSlug(subdomain);
            if (slug is null || options.ReservedSubdomains.Contains(slug, StringComparer.OrdinalIgnoreCase))
            {
                continue;
            }

            return slug;
        }

        return null;
    }

    private static string? NormalizeSlug(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return null;
        }

        var slug = value.Trim().ToLowerInvariant();
        return TenantSlugRegex().IsMatch(slug) ? slug : null;
    }

    [GeneratedRegex("^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$", RegexOptions.CultureInvariant)]
    private static partial Regex TenantSlugRegex();
}
