// <copyright file="TenantResolutionMiddleware.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using Microsoft.Extensions.Options;
using Norge360.AspNetCore.ProblemDetails;
using Norge360.Auth.Application.Abstractions;
using Norge360.Auth.Application.Options;
using Norge360.Auth.Application.Records;

namespace Norge360.Auth.API.Middlewares;

public sealed class TenantResolutionMiddleware(
    RequestDelegate next,
    IOptions<TenantResolutionOptions> options,
    ILogger<TenantResolutionMiddleware> logger)
{
    private const string TenantContextItemName = "TenantContext";

    private static readonly PathString[] AnonymousAllowedPrefixes =
    [
        new("/health"),
        new("/.well-known"),
        new("/swagger")
    ];

    public async Task InvokeAsync(HttpContext context, ITenantRepository tenantRepository)
    {
        var value = options.Value;
        if (IsTenantOptionalPath(context.Request.Path, value))
        {
            await next(context);
            return;
        }

        var trustedRequest = TrustedGatewayMiddleware.IsTrustedGatewayRequest(context);
        TenantContext? tenantContext = null;

        if (trustedRequest)
        {
            var tenantIdHeader = context.Request.Headers[value.HeaderName].FirstOrDefault();
            if (Guid.TryParse(tenantIdHeader, out var tenantId))
            {
                tenantContext = new TenantContext(tenantId, null, "header", true);
            }
            else
            {
                var slugHeader = context.Request.Headers[value.SlugHeaderName].FirstOrDefault();
                if (!string.IsNullOrWhiteSpace(slugHeader))
                {
                    tenantContext = new TenantContext(null, slugHeader.Trim().ToLowerInvariant(), "slug-header", true);
                }
                else
                {
                    var host = context.Request.Host.Host;
                    foreach (var suffix in value.TrustedHostSuffixes)
                    {
                        if (!host.EndsWith(suffix, StringComparison.OrdinalIgnoreCase))
                        {
                            continue;
                        }

                        var subdomain = host[..^suffix.Length].TrimEnd('.');
                        if (!string.IsNullOrWhiteSpace(subdomain) &&
                            !subdomain.Equals("auth", StringComparison.OrdinalIgnoreCase))
                        {
                            tenantContext = new TenantContext(null, subdomain.ToLowerInvariant(), "host", true);
                            break;
                        }
                    }
                }
            }
        }

        if (tenantContext is { TenantId: null, TenantSlug: not null } unresolvedBySlug)
        {
            var tenant = await tenantRepository.GetBySlugAsync(unresolvedBySlug.TenantSlug, context.RequestAborted);
            if (tenant is not null)
            {
                tenantContext = unresolvedBySlug with { TenantId = tenant.Id };
            }
        }

        if (tenantContext is null && value.RequireResolvedTenant && !value.AllowBodyFallback)
        {
            logger.LogWarning("Tenant could not be resolved for {Path}.", context.Request.Path);

            await ProblemDetailsSupport.WriteProblemAsync(
                context,
                StatusCodes.Status400BadRequest,
                "Tenant resolution failed",
                "Tenant context is required for this request.",
                errorCode: "tenant_resolution_failed",
                cancellationToken: context.RequestAborted);

            return;
        }

        if (tenantContext is not null)
        {
            context.Items[TenantContextItemName] = tenantContext;
        }

        await next(context);
    }

    public static TenantContext? GetTenantContext(HttpContext context) =>
        context.Items.TryGetValue(TenantContextItemName, out var value)
            ? value as TenantContext
            : null;

    private static bool IsTenantOptionalPath(PathString path, TenantResolutionOptions options) =>
        AnonymousAllowedPrefixes.Any(prefix => path.StartsWithSegments(prefix)) ||
        options.TenantOptionalPathPrefixes
            .Where(prefix => !string.IsNullOrWhiteSpace(prefix))
            .Select(prefix => new PathString(prefix.Trim()))
            .Any(prefix => path.StartsWithSegments(prefix));
}
