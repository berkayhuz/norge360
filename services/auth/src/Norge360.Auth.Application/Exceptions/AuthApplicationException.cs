// <copyright file="AuthApplicationException.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

namespace Norge360.Auth.Application.Exceptions;

public sealed class AuthApplicationException(
    string title,
    string detail,
    int statusCode,
    string? errorCode = null,
    string? type = null) : Exception(detail)
{
    public string Title { get; } = title;
    public int StatusCode { get; } = statusCode;
    public string? ErrorCode { get; } = errorCode;
    public string Type { get; } = type ?? $"https://httpstatuses.com/{statusCode}";
}
