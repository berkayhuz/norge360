// <copyright file="ExternalEndpointGuard.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using System.Net;
using System.Net.Sockets;

namespace Norge360.Security.EndpointGuard;

public static class ExternalEndpointGuard
{
    private static readonly string[] DisallowedHostSuffixes =
    [
        ".internal",
        ".local",
        ".lan",
        ".corp",
        ".home",
        ".localhost"
    ];

    private static readonly string[] AllowedSecretReferenceSchemes =
    [
        "secret",
        "vault",
        "keyvault",
        "azure-keyvault",
        "aws-secretsmanager",
        "gcp-secretmanager"
    ];

    public static bool IsTrustedHttpsEndpoint(string? targetUrl)
        => IsTrustedHttpsEndpoint(targetUrl, Dns.GetHostAddresses);

    public static bool IsTrustedHttpsEndpoint(string? targetUrl, Func<string, IPAddress[]> resolveHost)
    {
        if (string.IsNullOrWhiteSpace(targetUrl))
            return false;

        if (!Uri.TryCreate(targetUrl.Trim(), UriKind.Absolute, out var uri))
            return false;

        if (!string.Equals(uri.Scheme, Uri.UriSchemeHttps, StringComparison.OrdinalIgnoreCase))
            return false;

        if (!string.IsNullOrEmpty(uri.UserInfo) || uri.IsLoopback)
            return false;

        if (uri.Port is not (-1 or 443))
            return false;

        return IsPublicDnsHost(uri.IdnHost, resolveHost);
    }

    public static bool IsPublicDnsHost(string? host)
        => IsPublicDnsHost(host, Dns.GetHostAddresses);

    public static bool IsPublicDnsHost(string? host, Func<string, IPAddress[]> resolveHost)
    {
        if (string.IsNullOrWhiteSpace(host))
            return false;

        var normalizedHost = host.Trim().TrimEnd('.');
        if (string.IsNullOrWhiteSpace(normalizedHost))
            return false;

        if (IPAddress.TryParse(normalizedHost, out _))
            return false;

        if (!normalizedHost.Contains('.', StringComparison.Ordinal) ||
            string.Equals(normalizedHost, "localhost", StringComparison.OrdinalIgnoreCase))
        {
            return false;
        }

        if (DisallowedHostSuffixes.Any(suffix => normalizedHost.EndsWith(suffix, StringComparison.OrdinalIgnoreCase)))
            return false;

        try
        {
            var addresses = resolveHost(normalizedHost);
            return addresses.Length > 0 && addresses.All(IsPublicAddress);
        }
        catch (SocketException)
        {
            return false;
        }
    }

    public static bool IsSecretReference(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
            return false;

        var trimmed = value.Trim();
        return Uri.TryCreate(trimmed, UriKind.Absolute, out var uri) &&
               AllowedSecretReferenceSchemes.Any(scheme => string.Equals(uri.Scheme, scheme, StringComparison.OrdinalIgnoreCase)) &&
               string.IsNullOrEmpty(uri.UserInfo) &&
               string.IsNullOrEmpty(uri.Query) &&
               string.IsNullOrEmpty(uri.Fragment) &&
               trimmed.Length <= 300;
    }

    private static bool IsPublicAddress(IPAddress address)
    {
        if (IPAddress.IsLoopback(address))
            return false;

        if (address.AddressFamily == AddressFamily.InterNetworkV6)
        {
            if (address.IsIPv6LinkLocal ||
                address.IsIPv6SiteLocal ||
                address.IsIPv6Multicast ||
                address.Equals(IPAddress.IPv6Loopback) ||
                address.Equals(IPAddress.IPv6None))
            {
                return false;
            }

            return !address.IsIPv4MappedToIPv6 || IsPublicAddress(address.MapToIPv4());
        }

        var bytes = address.GetAddressBytes();
        return bytes switch
        {
            [10, ..] => false,
            [127, ..] => false,
            [169, 254, ..] => false,
            [172, >= 16 and <= 31, ..] => false,
            [192, 168, ..] => false,
            [0, ..] => false,
            [100, >= 64 and <= 127, ..] => false,
            [192, 0, 0, ..] => false,
            [192, 0, 2, ..] => false,
            [198, 18 or 19, ..] => false,
            [198, 51, 100, ..] => false,
            [203, 0, 113, ..] => false,
            [>= 224, ..] => false,
            _ => true
        };
    }
}
