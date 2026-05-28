// <copyright file="RecoveryCodeService.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using System.Security.Cryptography;
using System.Text;
using Norge360.Auth.Application.Abstractions;

namespace Norge360.Auth.Infrastructure.Services;

public sealed class RecoveryCodeService : IRecoveryCodeService
{
    public IReadOnlyCollection<string> GenerateCodes(int count)
    {
        var codes = new string[count];
        for (var i = 0; i < count; i++)
        {
            var bytes = new byte[10];
            RandomNumberGenerator.Fill(bytes);
            codes[i] = Convert.ToHexString(bytes).Insert(10, "-");
        }

        return codes;
    }

    public string HashCode(Guid tenantId, Guid userId, string code)
    {
        var normalized = code.Trim().Replace("-", string.Empty, StringComparison.Ordinal).ToUpperInvariant();
        var input = $"{tenantId:N}:{userId:N}:{normalized}";
        return Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(input)));
    }
}
