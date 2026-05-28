// <copyright file="AuthenticatorTotpService.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using System.Globalization;
using System.Security.Cryptography;
using Norge360.Auth.Application.Abstractions;

namespace Norge360.Auth.Infrastructure.Services;

public sealed class AuthenticatorTotpService : IAuthenticatorTotpService
{
    private const int SharedKeyBytes = 20;
    private static readonly char[] Base32Alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567".ToCharArray();

    public string GenerateSharedKey()
    {
        Span<byte> bytes = stackalloc byte[SharedKeyBytes];
        RandomNumberGenerator.Fill(bytes);
        return ToBase32(bytes);
    }

    public string BuildAuthenticatorUri(string issuer, string accountName, string sharedKey)
    {
        var safeIssuer = string.IsNullOrWhiteSpace(issuer) ? "Norge360" : issuer.Trim();
        var label = $"{safeIssuer}:{accountName}";
        return string.Create(
            CultureInfo.InvariantCulture,
            $"otpauth://totp/{Uri.EscapeDataString(label)}?secret={sharedKey}&issuer={Uri.EscapeDataString(safeIssuer)}&algorithm=SHA256&digits=6&period=30");
    }

    public bool VerifyCode(string sharedKey, string verificationCode, DateTime utcNow)
    {
        if (verificationCode.Length != 6 || verificationCode.Any(ch => !char.IsDigit(ch)))
        {
            return false;
        }

        var key = FromBase32(sharedKey);
        var timeStep = new DateTimeOffset(DateTime.SpecifyKind(utcNow, DateTimeKind.Utc)).ToUnixTimeSeconds() / 30;

        for (var offset = -1; offset <= 1; offset++)
        {
            var expected = ComputeCode(key, timeStep + offset);
            if (CryptographicOperations.FixedTimeEquals(
                    System.Text.Encoding.ASCII.GetBytes(expected),
                    System.Text.Encoding.ASCII.GetBytes(verificationCode)))
            {
                return true;
            }
        }

        return false;
    }

    private static string ComputeCode(byte[] key, long timeStep)
    {
        Span<byte> counter = stackalloc byte[8];
        var networkOrder = timeStep;
        for (var i = 7; i >= 0; i--)
        {
            counter[i] = (byte)(networkOrder & 0xFF);
            networkOrder >>= 8;
        }

        using var hmac = new HMACSHA256(key);
        var hash = hmac.ComputeHash(counter.ToArray());
        var offset = hash[^1] & 0x0F;
        var binary =
            ((hash[offset] & 0x7F) << 24) |
            ((hash[offset + 1] & 0xFF) << 16) |
            ((hash[offset + 2] & 0xFF) << 8) |
            (hash[offset + 3] & 0xFF);

        return (binary % 1_000_000).ToString("D6", CultureInfo.InvariantCulture);
    }

    private static string ToBase32(ReadOnlySpan<byte> bytes)
    {
        var output = new char[(int)Math.Ceiling(bytes.Length / 5d) * 8];
        var bitBuffer = 0;
        var bitCount = 0;
        var outputIndex = 0;

        foreach (var value in bytes)
        {
            bitBuffer = (bitBuffer << 8) | value;
            bitCount += 8;

            while (bitCount >= 5)
            {
                output[outputIndex++] = Base32Alphabet[(bitBuffer >> (bitCount - 5)) & 31];
                bitCount -= 5;
            }
        }

        if (bitCount > 0)
        {
            output[outputIndex++] = Base32Alphabet[(bitBuffer << (5 - bitCount)) & 31];
        }

        return new string(output, 0, outputIndex);
    }

    private static byte[] FromBase32(string value)
    {
        var clean = value.Trim().Replace(" ", string.Empty, StringComparison.Ordinal).TrimEnd('=').ToUpperInvariant();
        var bytes = new List<byte>(clean.Length * 5 / 8);
        var bitBuffer = 0;
        var bitCount = 0;

        foreach (var ch in clean)
        {
            var index = Array.IndexOf(Base32Alphabet, ch);
            if (index < 0)
            {
                throw new InvalidOperationException("Authenticator key contains invalid base32 characters.");
            }

            bitBuffer = (bitBuffer << 5) | index;
            bitCount += 5;

            if (bitCount >= 8)
            {
                bytes.Add((byte)((bitBuffer >> (bitCount - 8)) & 0xFF));
                bitCount -= 8;
            }
        }

        return bytes.ToArray();
    }
}
