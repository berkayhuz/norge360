// <copyright file="RefreshTokenService.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using System.Security.Cryptography;
using System.Text;
using Microsoft.Extensions.Options;
using Norge360.Auth.Application.Abstractions;
using Norge360.Auth.Application.Descriptors;
using Norge360.Auth.Application.Options;
using Norge360.Clock;

namespace Norge360.Auth.Infrastructure.Services;

public sealed class RefreshTokenService(IOptions<JwtOptions> jwtOptions, IClock clock) : IRefreshTokenService
{
    public RefreshTokenDescriptor Generate(bool isPersistent)
    {
        Span<byte> bytes = stackalloc byte[64];
        RandomNumberGenerator.Fill(bytes);
        var token = Convert.ToBase64String(bytes);
        var expiresAt = isPersistent
            ? clock.UtcDateTime.AddDays(jwtOptions.Value.RefreshTokenPersistentDays)
            : clock.UtcDateTime.AddHours(jwtOptions.Value.RefreshTokenHours);
        return new RefreshTokenDescriptor(token, Hash(token), expiresAt);
    }

    public bool Verify(string refreshToken, string refreshTokenHash)
    {
        var candidateHash = Hash(refreshToken);
        return CryptographicOperations.FixedTimeEquals(
            Encoding.UTF8.GetBytes(candidateHash),
            Encoding.UTF8.GetBytes(refreshTokenHash));
    }

    private static string Hash(string token)
    {
        var bytes = SHA256.HashData(Encoding.UTF8.GetBytes(token));
        return Convert.ToHexString(bytes);
    }
}
