// <copyright file="AuthVerificationTokenPurpose.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

namespace Norge360.Auth.Domain.Entities;

public static class AuthVerificationTokenPurpose
{
    public const string EmailConfirmation = "email-confirmation";
    public const string PasswordReset = "password-reset";
    public const string EmailChange = "email-change";
}
