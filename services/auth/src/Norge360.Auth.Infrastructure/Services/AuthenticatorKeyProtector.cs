// <copyright file="AuthenticatorKeyProtector.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using Microsoft.AspNetCore.DataProtection;
using Norge360.Auth.Application.Abstractions;

namespace Norge360.Auth.Infrastructure.Services;

public sealed class AuthenticatorKeyProtector(IDataProtectionProvider dataProtectionProvider) : IAuthenticatorKeyProtector
{
    private readonly IDataProtector _protector = dataProtectionProvider.CreateProtector("Norge360.Auth.Mfa.AuthenticatorKey.v1");

    public string Protect(string sharedKey) => _protector.Protect(sharedKey);

    public string Unprotect(string protectedSharedKey) => _protector.Unprotect(protectedSharedKey);
}
