// <copyright file="SecuritySupport.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using System.Net;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.HttpOverrides;
using IPNetwork = System.Net.IPNetwork;

namespace Norge360.AspNetCore.Security;

public static class SecuritySupport
{
    public static void ApplySecurityHeaders(HttpContext context, SecurityHeadersValues values)
    {
        if (!context.Response.HasStarted)
        {
            Apply();
        }

        context.Response.OnStarting(() =>
        {
            Apply();
            return Task.CompletedTask;
        });

        void Apply()
        {
            var headers = context.Response.Headers;
            headers.XContentTypeOptions = "nosniff";
            headers.XFrameOptions = "DENY";
            headers["Referrer-Policy"] = values.ReferrerPolicy;
            headers.ContentSecurityPolicy = values.ContentSecurityPolicy;
            headers["Permissions-Policy"] = values.PermissionsPolicy;
            headers["X-Permitted-Cross-Domain-Policies"] = "none";
            headers["Cross-Origin-Opener-Policy"] = "same-origin";

            if (values.DisableResponseCaching)
            {
                headers.CacheControl = "no-store";
                headers.Pragma = "no-cache";
            }

            if (context.Request.IsHttps && values.EnableHsts)
            {
                var hstsValue = $"max-age={values.HstsMaxAgeSeconds}";
                if (values.IncludeSubDomains)
                {
                    hstsValue += "; includeSubDomains";
                }

                if (values.PreloadHsts)
                {
                    hstsValue += "; preload";
                }

                headers.StrictTransportSecurity = hstsValue;
            }
        }
    }

    public static void ConfigureForwardedHeaders(
        ForwardedHeadersOptions target,
        int forwardLimit,
        IEnumerable<string> knownProxies,
        IEnumerable<string> knownNetworks)
    {
        target.ForwardedHeaders =
            ForwardedHeaders.XForwardedFor |
            ForwardedHeaders.XForwardedProto |
            ForwardedHeaders.XForwardedHost;
        target.ForwardLimit = forwardLimit;
        target.KnownProxies.Clear();
        target.KnownIPNetworks.Clear();

        foreach (var proxy in knownProxies)
        {
            if (IPAddress.TryParse(proxy, out var address))
            {
                target.KnownProxies.Add(address);
            }
        }

        foreach (var network in knownNetworks)
        {
            if (TryParseNetwork(network, out var parsedNetwork))
            {
                target.KnownIPNetworks.Add(parsedNetwork);
            }
        }
    }

    public static bool TryParseNetwork(string value, out IPNetwork network)
    {
        network = default;
        var segments = value.Split('/', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries);
        if (segments.Length != 2 ||
            !IPAddress.TryParse(segments[0], out var prefix) ||
            !int.TryParse(segments[1], out var prefixLength))
        {
            return false;
        }

        network = new IPNetwork(prefix, prefixLength);
        return true;
    }

    public static bool IsValidOrigin(string value, bool allowHttpForLocalhostOnly)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return false;
        }

        var origin = value.AsSpan().Trim();
        if (origin.IndexOfAny('?', '#') >= 0)
        {
            return false;
        }

        var isHttps = origin.StartsWith("https://", StringComparison.OrdinalIgnoreCase);
        var isHttp = !isHttps && origin.StartsWith("http://", StringComparison.OrdinalIgnoreCase);
        if (!isHttps && !isHttp)
        {
            return false;
        }

        var authorityAndPath = origin[(isHttps ? "https://".Length : "http://".Length)..];
        if (authorityAndPath.IsEmpty)
        {
            return false;
        }

        var slashIndex = authorityAndPath.IndexOf('/');
        ReadOnlySpan<char> authority;
        if (slashIndex < 0)
        {
            authority = authorityAndPath;
        }
        else
        {
            var path = authorityAndPath[slashIndex..];
            if (path.Length > 1)
            {
                return false;
            }

            authority = authorityAndPath[..slashIndex];
        }

        if (!TryParseAuthority(authority, out var host))
        {
            return false;
        }

        if (isHttps)
        {
            return IsValidHost(host);
        }

        return allowHttpForLocalhostOnly &&
               (host.Equals("localhost", StringComparison.OrdinalIgnoreCase) ||
                host.SequenceEqual("127.0.0.1".AsSpan()));
    }

    public static bool LooksLikeHostName(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return false;
        }

        return !value.Contains('/') &&
               !value.Contains("://", StringComparison.Ordinal) &&
               Uri.CheckHostName(value) != UriHostNameType.Unknown;
    }

    public static bool IsAllowedRemoteAddress(IPAddress? address, IEnumerable<string> exactAddresses, IEnumerable<string> networks)
    {
        if (address is null)
        {
            return false;
        }

        var proxyMatches = exactAddresses.Any(candidate => IPAddress.TryParse(candidate, out var parsed) && parsed.Equals(address));
        if (proxyMatches)
        {
            return true;
        }

        foreach (var network in networks)
        {
            if (TryParseNetwork(network, out var parsedNetwork) && parsedNetwork.Contains(address))
            {
                return true;
            }
        }

        return false;
    }

    private static bool TryParseAuthority(ReadOnlySpan<char> authority, out ReadOnlySpan<char> host)
    {
        host = default;
        if (authority.IsEmpty || authority.IndexOf('@') >= 0)
        {
            return false;
        }

        if (authority[0] == '[')
        {
            var closingBracket = authority.IndexOf(']');
            if (closingBracket <= 1)
            {
                return false;
            }

            host = authority[1..closingBracket];
            if (closingBracket == authority.Length - 1)
            {
                return true;
            }

            if (authority[closingBracket + 1] != ':')
            {
                return false;
            }

            return IsValidPort(authority[(closingBracket + 2)..]);
        }

        var lastColon = authority.LastIndexOf(':');
        if (lastColon > 0 && authority[..lastColon].IndexOf(':') < 0)
        {
            host = authority[..lastColon];
            return IsValidPort(authority[(lastColon + 1)..]);
        }

        host = authority;
        return true;
    }

    private static bool IsValidPort(ReadOnlySpan<char> port)
    {
        if (port.IsEmpty)
        {
            return false;
        }

        var value = 0;
        foreach (var c in port)
        {
            if (c is < '0' or > '9')
            {
                return false;
            }

            value = (value * 10) + (c - '0');
            if (value > 65535)
            {
                return false;
            }
        }

        return true;
    }

    private static bool IsValidHost(ReadOnlySpan<char> host)
    {
        if (host.IsEmpty)
        {
            return false;
        }

        if (host.Equals("localhost", StringComparison.OrdinalIgnoreCase))
        {
            return true;
        }

        if (IPAddress.TryParse(host, out _))
        {
            return true;
        }

        if (host.Length > 253)
        {
            return false;
        }

        var labelLength = 0;
        var hasDot = false;
        for (var i = 0; i < host.Length; i++)
        {
            var c = host[i];
            if (c == '.')
            {
                if (labelLength is 0 or > 63 || host[i - 1] == '-')
                {
                    return false;
                }

                hasDot = true;
                labelLength = 0;
                continue;
            }

            var isLetterOrDigit = char.IsAsciiLetterOrDigit(c);
            if (!isLetterOrDigit && c != '-')
            {
                return false;
            }

            if (labelLength == 0 && c == '-')
            {
                return false;
            }

            labelLength++;
        }

        if (labelLength is 0 or > 63 || host[^1] == '-')
        {
            return false;
        }

        return hasDot || labelLength > 0;
    }
}
