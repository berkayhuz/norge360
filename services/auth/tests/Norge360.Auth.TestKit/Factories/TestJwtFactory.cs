// <copyright file="TestJwtFactory.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Security.Cryptography;
using Microsoft.IdentityModel.Tokens;

namespace Norge360.Auth.TestKit.Factories;

public sealed class TestJwtFactory : IDisposable
{
    private readonly RSA _privateKey;

    public TestJwtFactory()
    {
        _privateKey = RSA.Create(2048);
    }

    public string ExportPrivateKeyPem()
    {
        var pem = _privateKey.ExportRSAPrivateKeyPem();
        return pem;
    }

    public string CreateToken(
        Guid userId,
        Guid sessionId,
        int tokenVersion,
        string issuer,
        string audience,
        DateTime? utcNow = null)
    {
        var now = utcNow ?? new DateTime(2026, 1, 1, 0, 0, 0, DateTimeKind.Utc);
        var credentials = new SigningCredentials(new RsaSecurityKey(_privateKey) { KeyId = "test-key-01" }, SecurityAlgorithms.RsaSha256);
        var claims = new[]
        {
            new Claim(JwtRegisteredClaimNames.Sub, userId.ToString()),
            new Claim(JwtRegisteredClaimNames.Sid, sessionId.ToString()),
            new Claim("token_version", tokenVersion.ToString())
        };

        var token = new JwtSecurityToken(
            issuer: issuer,
            audience: audience,
            claims: claims,
            notBefore: now,
            expires: now.AddMinutes(15),
            signingCredentials: credentials);

        return new JwtSecurityTokenHandler().WriteToken(token);
    }

    public void Dispose()
    {
        _privateKey.Dispose();
    }
}
