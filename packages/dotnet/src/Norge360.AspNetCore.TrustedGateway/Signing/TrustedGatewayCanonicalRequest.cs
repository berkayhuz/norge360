// <copyright file="TrustedGatewayCanonicalRequest.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using System.Security.Cryptography;
using System.Text;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Primitives;

namespace Norge360.AspNetCore.TrustedGateway.Signing;

public static class TrustedGatewayCanonicalRequest
{
    private static readonly string EmptyBodyHash = Convert.ToHexString(SHA256.HashData(Array.Empty<byte>()));

    public static async Task<string> BuildAsync(
        HttpRequest request,
        string timestamp,
        string nonce,
        string correlationId,
        string source,
        string contentHash,
        CancellationToken cancellationToken)
    {
        var normalizedPath = NormalizePath(request.Path.Value);
        var normalizedQuery = NormalizeQuery(request.Query);
        var normalizedContentType = NormalizeContentType(request.ContentType);

        await EnsureBufferedAsync(request, cancellationToken);

        return string.Join('\n',
            request.Method.ToUpperInvariant(),
            normalizedPath,
            normalizedQuery,
            timestamp,
            nonce,
            correlationId,
            normalizedContentType,
            source,
            contentHash);
    }

    public static async Task<string> ComputeBodyHashAsync(HttpRequest request, CancellationToken cancellationToken)
    {
        if (request.Body is null)
        {
            return EmptyBodyHash;
        }

        await EnsureBufferedAsync(request, cancellationToken);
        request.Body.Position = 0;

        using var sha256 = SHA256.Create();
        var hash = await sha256.ComputeHashAsync(request.Body, cancellationToken);
        request.Body.Position = 0;
        return hash.Length == 0 ? EmptyBodyHash : Convert.ToHexString(hash);
    }

    private static async Task EnsureBufferedAsync(HttpRequest request, CancellationToken cancellationToken)
    {
        request.EnableBuffering();

        if (!request.Body.CanSeek)
        {
            await request.Body.CopyToAsync(Stream.Null, cancellationToken);
        }
    }

    private static string NormalizePath(string? rawPath)
    {
        if (string.IsNullOrWhiteSpace(rawPath))
        {
            return "/";
        }

        var hasTrailingSlash = rawPath.Length > 1 && rawPath[^1] == '/';
        var parts = rawPath.Split('/', StringSplitOptions.RemoveEmptyEntries);
        if (parts.Length == 0)
        {
            return "/";
        }

        var builder = new StringBuilder(rawPath.Length + 8);
        builder.Append('/');
        for (var i = 0; i < parts.Length; i++)
        {
            if (i > 0)
            {
                builder.Append('/');
            }

            builder.Append(Uri.EscapeDataString(parts[i]));
        }

        if (hasTrailingSlash)
        {
            builder.Append('/');
        }

        return builder.ToString();
    }

    private static string NormalizeQuery(IQueryCollection query)
    {
        if (query.Count == 0)
        {
            return string.Empty;
        }

        var keys = query.Keys.ToArray();
        Array.Sort(keys, StringComparer.Ordinal);

        var builder = new StringBuilder(query.Count * 16);
        var appendAmpersand = false;
        foreach (var key in keys)
        {
            var encodedKey = Uri.EscapeDataString(key);
            var values = query[key];
            if (StringValues.IsNullOrEmpty(values))
            {
                if (appendAmpersand)
                {
                    builder.Append('&');
                }

                builder.Append(encodedKey);
                builder.Append('=');
                appendAmpersand = true;
                continue;
            }

            var sortedValues = values.ToArray();
            Array.Sort(sortedValues, StringComparer.Ordinal);

            foreach (var value in sortedValues)
            {
                if (appendAmpersand)
                {
                    builder.Append('&');
                }

                builder.Append(encodedKey);
                builder.Append('=');
                builder.Append(Uri.EscapeDataString(value ?? string.Empty));
                appendAmpersand = true;
            }
        }

        return builder.ToString();
    }

    private static string NormalizeContentType(string? contentType) =>
        string.IsNullOrWhiteSpace(contentType)
            ? string.Empty
            : contentType.Trim().ToLowerInvariant();
}
