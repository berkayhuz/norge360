// <copyright file="TrustedGatewaySigner.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using Microsoft.AspNetCore.Http;
using Norge360.AspNetCore.TrustedGateway.Abstractions;
using Norge360.AspNetCore.TrustedGateway.Models;
using Norge360.AspNetCore.TrustedGateway.Options;

namespace Norge360.AspNetCore.TrustedGateway.Signing;

public sealed class TrustedGatewaySigner(TrustedGatewayOptions options) : ITrustedGatewaySigner
{
    public async Task<TrustedGatewaySignedHeaders> SignAsync(HttpRequest request, string correlationId, CancellationToken cancellationToken)
    {
        var signingKey = options.Keys.FirstOrDefault(x =>
                x.Enabled &&
                x.SignRequests &&
                string.Equals(x.KeyId, options.CurrentKeyId, StringComparison.Ordinal))
            ?? throw new InvalidOperationException("Security:TrustedGateway current signing key is missing or disabled.");

        var timestamp = DateTimeOffset.UtcNow.ToUnixTimeSeconds().ToString(CultureInfo.InvariantCulture);
        var nonce = Guid.NewGuid().ToString("N");
        var contentHash = await TrustedGatewayCanonicalRequest.ComputeBodyHashAsync(request, cancellationToken);
        var canonical = await TrustedGatewayCanonicalRequest.BuildAsync(
            request,
            timestamp,
            nonce,
            correlationId,
            options.Source,
            contentHash,
            cancellationToken);

        var signature = ComputeSignature(signingKey.Secret, canonical);

        return new TrustedGatewaySignedHeaders(
            signature,
            timestamp,
            signingKey.KeyId,
            options.Source,
            nonce,
            contentHash,
            correlationId);
    }

    private static string ComputeSignature(string secret, string canonical)
    {
        using var hmac = new HMACSHA256(Encoding.UTF8.GetBytes(secret));
        return Convert.ToHexString(hmac.ComputeHash(Encoding.UTF8.GetBytes(canonical)));
    }
}
