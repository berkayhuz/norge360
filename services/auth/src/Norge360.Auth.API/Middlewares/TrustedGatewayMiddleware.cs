// <copyright file="TrustedGatewayMiddleware.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using Microsoft.Extensions.Options;
using Norge360.AspNetCore.ProblemDetails;
using Norge360.AspNetCore.RequestContext;
using Norge360.AspNetCore.TrustedGateway.Abstractions;
using Norge360.AspNetCore.TrustedGateway.Options;
using Norge360.Auth.Application.Abstractions;
using Norge360.Auth.Application.Diagnostics;
using Norge360.Auth.Application.Records;

namespace Norge360.Auth.API.Middlewares;

public sealed class TrustedGatewayMiddleware(
    RequestDelegate next,
    IOptions<TrustedGatewayOptions> options,
    ITrustedGatewayRequestValidator trustedGatewayRequestValidator,
    ISecurityAlertPublisher securityAlertPublisher,
    ILogger<TrustedGatewayMiddleware> logger)
{
    public const string TrustedGatewayValidatedItemName = "TrustedGatewayValidated";

    private static readonly PathString[] AnonymousAllowedPrefixes =
    [
        new("/health"),
        new("/.well-known"),
        new("/swagger")
    ];

    public async Task InvokeAsync(HttpContext context)
    {
        var value = options.Value;

        if (!value.RequireTrustedGateway || AnonymousAllowedPrefixes.Any(prefix => context.Request.Path.StartsWithSegments(prefix)))
        {
            await next(context);
            return;
        }

        var correlationId = RequestContextSupport.GetOrCreateCorrelationId(context);
        var validationResult = await trustedGatewayRequestValidator.ValidateAsync(context, correlationId, context.RequestAborted);

        if (!validationResult.Succeeded)
        {
            AuthMetrics.TrustedGatewayRejected.Add(1, new KeyValuePair<string, object?>("reason", validationResult.FailureReason.ToString()));

            logger.LogWarning(
                "Trusted gateway validation rejected request for {Path}. Reason={Reason} CorrelationId={CorrelationId}",
                context.Request.Path,
                validationResult.FailureReason,
                correlationId);

            await securityAlertPublisher.PublishAsync(
                new SecurityAlert(
                    "auth.trusted-gateway.rejected",
                    "critical",
                    "Trusted gateway validation rejected request.",
                    Guid.Empty,
                    null,
                    null,
                    correlationId,
                    context.TraceIdentifier,
                    $"path={context.Request.Path};reason={validationResult.FailureReason}"),
                context.RequestAborted);

            await ProblemDetailsSupport.WriteProblemAsync(
                context,
                StatusCodes.Status403Forbidden,
                "Trusted caller required",
                "The auth service only accepts traffic from a trusted gateway.",
                errorCode: validationResult.ErrorCode ?? "trusted_gateway_required",
                cancellationToken: context.RequestAborted);

            return;
        }

        context.Items[TrustedGatewayValidatedItemName] = true;
        await next(context);
    }

    public static bool IsTrustedGatewayRequest(HttpContext context) =>
        context.Items.TryGetValue(TrustedGatewayValidatedItemName, out var value) &&
        value is true;
}
