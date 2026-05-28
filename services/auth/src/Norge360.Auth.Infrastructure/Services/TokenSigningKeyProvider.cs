// <copyright file="TokenSigningKeyProvider.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using System.IO;
using System.Security.Cryptography;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Options;
using Microsoft.IdentityModel.Tokens;
using Norge360.Auth.Application.Abstractions;
using Norge360.Auth.Application.Options;

namespace Norge360.Auth.Infrastructure.Services;

public sealed class TokenSigningKeyProvider : ITokenSigningKeyProvider
{
    private readonly JwtOptions _options;
    private readonly IHostEnvironment _environment;
    private readonly Lazy<KeyRing> _keyRing;

    public TokenSigningKeyProvider(IOptions<JwtOptions> options, IHostEnvironment environment)
    {
        _options = options.Value;
        _environment = environment;
        _keyRing = new Lazy<KeyRing>(CreateKeyRing, true);
    }

    public SigningCredentials GetCurrentSigningCredentials() =>
        new(_keyRing.Value.Current.PrivateKey, SecurityAlgorithms.RsaSha256);

    public IReadOnlyCollection<SecurityKey> GetValidationKeys() =>
        _keyRing.Value.AllPublicKeys;

    public string CurrentKeyId => _keyRing.Value.Current.KeyId;

    public object GetJwksDocument(string issuer) => new
    {
        issuer,
        keys = _keyRing.Value.AllPublicKeys
            .OfType<RsaSecurityKey>()
            .Select(key => new
            {
                kty = "RSA",
                use = "sig",
                alg = "RS256",
                kid = key.KeyId,
                n = Base64UrlEncoder.Encode(key.Rsa.ExportParameters(false).Modulus),
                e = Base64UrlEncoder.Encode(key.Rsa.ExportParameters(false).Exponent)
            })
    };

    private KeyRing CreateKeyRing()
    {
        if (_options.SigningKeys.Length == 0)
        {
            if (_environment.IsDevelopment())
            {
                return CreateEphemeralDevelopmentKeyRing();
            }

            throw new InvalidOperationException("At least one Jwt signing key must be configured.");
        }

        var keys = _options.SigningKeys.Select(CreateConfiguredKey).ToArray();
        var current = keys.FirstOrDefault(x => x.IsCurrent) ?? keys[0];
        return new KeyRing(current, keys.Select(x => x.PublicKey).Cast<SecurityKey>().ToArray());
    }

    private static KeyRing CreateEphemeralDevelopmentKeyRing()
    {
        var keyId = $"auth-rsa-development-ephemeral-{Guid.NewGuid():N}";
        var signingRsa = RSA.Create(3072);

        var validationRsa = RSA.Create();
        validationRsa.ImportParameters(signingRsa.ExportParameters(false));

        var configured = new ConfiguredKey(
            keyId,
            true,
            new RsaSecurityKey(signingRsa) { KeyId = keyId },
            new RsaSecurityKey(validationRsa) { KeyId = keyId });

        return new KeyRing(configured, [configured.PublicKey]);
    }

    private static ConfiguredKey CreateConfiguredKey(JwtSigningKeyOptions keyOptions)
    {
        var pem = !string.IsNullOrWhiteSpace(keyOptions.PrivateKeyPath)
            ? File.ReadAllText(keyOptions.PrivateKeyPath)
            : keyOptions.PrivateKeyPem;

        using var rsa = RSA.Create();
        rsa.ImportFromPem(pem);

        var signingRsa = RSA.Create();
        signingRsa.ImportParameters(rsa.ExportParameters(true));

        var validationRsa = RSA.Create();
        validationRsa.ImportParameters(rsa.ExportParameters(false));

        return new ConfiguredKey(
            keyOptions.KeyId,
            keyOptions.IsCurrent,
            new RsaSecurityKey(signingRsa) { KeyId = keyOptions.KeyId },
            new RsaSecurityKey(validationRsa) { KeyId = keyOptions.KeyId });
    }

    private sealed record ConfiguredKey(string KeyId, bool IsCurrent, RsaSecurityKey PrivateKey, RsaSecurityKey PublicKey);

    private sealed record KeyRing(ConfiguredKey Current, IReadOnlyCollection<SecurityKey> AllPublicKeys);
}
