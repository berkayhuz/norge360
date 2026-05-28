// <copyright file="ProblemDetailsWriter.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using Norge360.AspNetCore.ProblemDetails;

namespace Norge360.Auth.API.Writers;

public static class ProblemDetailsWriter
{
    public static async Task WriteAsync(
        HttpContext context,
        int statusCode,
        string title,
        string detail,
        string? type = null,
        string? errorCode = null,
        CancellationToken cancellationToken = default)
    {
        await ProblemDetailsSupport.WriteProblemAsync(
            context,
            statusCode,
            title,
            detail,
            type,
            errorCode,
            cancellationToken);
    }
}
