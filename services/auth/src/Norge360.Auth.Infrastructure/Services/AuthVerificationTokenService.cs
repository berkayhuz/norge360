// <copyright file="AuthVerificationTokenService.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using System.Security.Cryptography;
using Microsoft.AspNetCore.WebUtilities;
using Microsoft.Extensions.Options;
using Norge360.Auth.Application.Abstractions;
using Norge360.Auth.Application.Options;

namespace Norge360.Auth.Infrastructure.Services;

public sealed class AuthVerificationTokenService(IOptions<AccountLifecycleOptions> options) : IAuthVerificationTokenService
{
    public string GenerateToken()
    {
        var tokenBytes = Math.Clamp(options.Value.TokenBytes, 32, 128);
        var bytes = new byte[tokenBytes];
        RandomNumberGenerator.Fill(bytes);
        return WebEncoders.Base64UrlEncode(bytes);
    }

    public string HashToken(string token)
    {
        var bytes = System.Text.Encoding.UTF8.GetBytes(token);
        var hash = SHA256.HashData(bytes);
        return Convert.ToHexString(hash);
    }
}
