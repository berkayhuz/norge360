// <copyright file="ProblemDetailsSupport.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.DependencyInjection;
using Norge360.AspNetCore.RequestContext;
using MvcProblemDetails = Microsoft.AspNetCore.Mvc.ProblemDetails;

namespace Norge360.AspNetCore.ProblemDetails;

public static class ProblemDetailsSupport
{
    public static IServiceCollection AddNorge360ProblemDetails(this IServiceCollection services)
    {
        services.AddProblemDetails(options =>
        {
            options.CustomizeProblemDetails = context =>
            {
                context.ProblemDetails.Extensions["traceId"] = RequestContextSupport.GetTraceId(context.HttpContext);
                context.ProblemDetails.Extensions["correlationId"] = RequestContextSupport.GetOrCreateCorrelationId(context.HttpContext);
            };
        });

        return services;
    }

    public static async Task WriteProblemAsync(
        HttpContext context,
        int statusCode,
        string title,
        string detail,
        string? type = null,
        string? errorCode = null,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();

        var problemDetailsService = context.RequestServices.GetRequiredService<IProblemDetailsService>();

        var problem = new MvcProblemDetails
        {
            Status = statusCode,
            Title = title,
            Detail = detail,
            Type = type ?? $"https://httpstatuses.com/{statusCode}",
            Instance = context.Request.Path
        };

        problem.Extensions["traceId"] = RequestContextSupport.GetTraceId(context);
        problem.Extensions["correlationId"] = RequestContextSupport.GetOrCreateCorrelationId(context);

        if (!string.IsNullOrWhiteSpace(errorCode))
        {
            problem.Extensions["errorCode"] = errorCode;
        }

        context.Response.StatusCode = statusCode;

        await problemDetailsService.TryWriteAsync(new ProblemDetailsContext
        {
            HttpContext = context,
            ProblemDetails = problem
        });
    }
}
