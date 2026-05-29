// <copyright file="AccountLifecycleOptions.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

namespace Norge360.Auth.Application.Options;

public sealed class AccountLifecycleOptions
{
    public const string SectionName = "AccountLifecycle";

    public bool RequireConfirmedEmailForLogin { get; set; } = true;
    public int EmailConfirmationTokenMinutes { get; set; } = 1440;
    public int PasswordResetTokenMinutes { get; set; } = 30;
    public int PasswordResetCooldownSeconds { get; set; } = 60;
    public int EmailChangeTokenMinutes { get; set; } = 30;
    public int EmailConfirmationResendCooldownSeconds { get; set; } = 120;
    public int TokenBytes { get; set; } = 32;
    public string PublicAppBaseUrl { get; set; } = "https://localhost:7025";
    public string ConfirmEmailPath { get; set; } = "/auth/confirm-email";
    public string ResetPasswordPath { get; set; } = "/auth/reset-password";
    public string ConfirmEmailChangePath { get; set; } = "/auth/confirm-email-change";
}
