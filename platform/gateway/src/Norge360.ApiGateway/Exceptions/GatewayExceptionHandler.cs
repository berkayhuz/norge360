// <copyright file="GatewayExceptionHandler.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using Microsoft.AspNetCore.Diagnostics;
using Norge360.AspNetCore.ProblemDetails;

namespace Norge360.ApiGateway.Exceptions;

public sealed class GatewayExceptionHandler(ILogger<GatewayExceptionHandler> logger) : IExceptionHandler
{
    public async ValueTask<bool> TryHandleAsync(HttpContext httpContext, Exception exception, CancellationToken cancellationToken)
    {
        logger.LogError(exception, "Unhandled gateway exception for {Path}", httpContext.Request.Path);

        await ProblemDetailsSupport.WriteProblemAsync(
            httpContext,
            StatusCodes.Status500InternalServerError,
            "Gateway request failed",
            "The gateway could not complete the request.",
            errorCode: "gateway_unhandled_exception",
            cancellationToken: cancellationToken);

        return true;
    }
}
