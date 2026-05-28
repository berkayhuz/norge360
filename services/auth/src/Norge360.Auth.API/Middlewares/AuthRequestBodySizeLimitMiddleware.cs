// <copyright file="AuthRequestBodySizeLimitMiddleware.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using Microsoft.AspNetCore.Http.Features;
using Norge360.AspNetCore.ProblemDetails;
using Norge360.Auth.API.Security;

namespace Norge360.Auth.API.Middlewares;

public sealed class AuthRequestBodySizeLimitMiddleware(RequestDelegate next)
{
    public async Task InvokeAsync(HttpContext context)
    {
        if (!IsAuthWriteRequest(context.Request))
        {
            await next(context);
            return;
        }

        var maxBodySizeFeature = context.Features.Get<IHttpMaxRequestBodySizeFeature>();
        if (maxBodySizeFeature is not null && !maxBodySizeFeature.IsReadOnly)
        {
            maxBodySizeFeature.MaxRequestBodySize = AuthRequestSizeLimits.AuthBodyBytes;
        }

        if (context.Request.ContentLength > AuthRequestSizeLimits.AuthBodyBytes)
        {
            await ProblemDetailsSupport.WriteProblemAsync(
                context,
                StatusCodes.Status413PayloadTooLarge,
                "Request body too large",
                "Authentication request bodies are limited to 16 KB.",
                errorCode: "auth_body_too_large",
                cancellationToken: context.RequestAborted);

            return;
        }

        await next(context);
    }

    private static bool IsAuthWriteRequest(HttpRequest request) =>
        HttpMethods.IsPost(request.Method) &&
        request.Path.StartsWithSegments("/api/auth", StringComparison.OrdinalIgnoreCase);
}
