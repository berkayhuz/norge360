// <copyright file="GatewayTrustedRequestTransform.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using Microsoft.Extensions.Options;
using Norge360.ApiGateway.Diagnostics;
using Norge360.AspNetCore.RequestContext;
using Norge360.AspNetCore.TrustedGateway.Abstractions;
using Norge360.AspNetCore.TrustedGateway.Options;
using Norge360.Localization;
using Yarp.ReverseProxy.Transforms;

namespace Norge360.ApiGateway.Security;

public sealed partial class GatewayTrustedRequestTransform(
    ITrustedGatewaySigner signer,
    IOptions<TrustedGatewayOptions> options,
    ILogger<GatewayTrustedRequestTransform> logger)
{
    private static readonly string[] SpoofableHeaders =
    [
        "X-Powered-By",
        RequestContextSupport.CorrelationIdHeaderName,
        "X-Original-Client-IP",
        Norge360Cultures.HeaderName
    ];

    public void ApplyCommonHeaders(RequestTransformContext context)
    {
        var trustedGatewayOptions = options.Value;

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

        var correlationId = RequestContextSupport.GetOrCreateCorrelationId(context.HttpContext);

        context.ProxyRequest.Headers.TryAddWithoutValidation(
            RequestContextSupport.CorrelationIdHeaderName,
            correlationId);

        context.ProxyRequest.Headers.TryAddWithoutValidation(
            "X-Original-Client-IP",
            context.HttpContext.Connection.RemoteIpAddress?.ToString() ?? "unknown");

        context.ProxyRequest.Headers.TryAddWithoutValidation(
            Norge360Cultures.HeaderName,
            ResolveCulture(context.HttpContext.Request));
    }

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

}
