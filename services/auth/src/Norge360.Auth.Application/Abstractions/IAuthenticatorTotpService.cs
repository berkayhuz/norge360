// <copyright file="IAuthenticatorTotpService.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

namespace Norge360.Auth.Application.Abstractions;

public interface IAuthenticatorTotpService
{
    string GenerateSharedKey();
    string BuildAuthenticatorUri(string issuer, string accountName, string sharedKey);
    bool VerifyCode(string sharedKey, string verificationCode, DateTime utcNow);
}
