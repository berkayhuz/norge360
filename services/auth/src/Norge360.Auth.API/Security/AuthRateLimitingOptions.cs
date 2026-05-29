// <copyright file="AuthRateLimitingOptions.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using System.Threading.RateLimiting;

namespace Norge360.Auth.API.Security;

public sealed class AuthRateLimitingOptions
{
    public const string SectionName = "Security:RateLimiting";
    public const string LoginPolicyName = "auth-login";
    public const string RegisterPolicyName = "auth-register";
    public const string RefreshPolicyName = "auth-refresh";
    public const string LogoutPolicyName = "auth-logout";
    public const string RoleManagementPolicyName = "auth-role-management";
    public const string PasswordRecoveryPolicyName = "auth-password-recovery";
    public const string EmailConfirmationPolicyName = "auth-email-confirmation";

    public FixedWindowRuleOptions Global { get; set; } = new(PermitLimit: 120, WindowSeconds: 60, QueueLimit: 0);

    public FixedWindowRuleOptions Login { get; set; } = new(PermitLimit: 5, WindowSeconds: 60, QueueLimit: 0);

    public FixedWindowRuleOptions Register { get; set; } = new(PermitLimit: 3, WindowSeconds: 300, QueueLimit: 0);

    public FixedWindowRuleOptions Refresh { get; set; } = new(PermitLimit: 10, WindowSeconds: 60, QueueLimit: 0);

    public FixedWindowRuleOptions Logout { get; set; } = new(PermitLimit: 20, WindowSeconds: 60, QueueLimit: 0);

    public FixedWindowRuleOptions RoleManagement { get; set; } = new(PermitLimit: 20, WindowSeconds: 300, QueueLimit: 0);

    public FixedWindowRuleOptions PasswordRecovery { get; set; } = new(PermitLimit: 3, WindowSeconds: 300, QueueLimit: 0);

    public FixedWindowRuleOptions EmailConfirmation { get; set; } = new(PermitLimit: 5, WindowSeconds: 300, QueueLimit: 0);
}

public sealed class FixedWindowRuleOptions
{
    public FixedWindowRuleOptions()
    {
    }

    public FixedWindowRuleOptions(int PermitLimit, int WindowSeconds, int QueueLimit)
    {
        this.PermitLimit = PermitLimit;
        this.WindowSeconds = WindowSeconds;
        this.QueueLimit = QueueLimit;
    }

    public int PermitLimit { get; set; }

    public int WindowSeconds { get; set; }

    public int QueueLimit { get; set; }

    public FixedWindowRateLimiterOptions ToLimiterOptions() => new()
    {
        PermitLimit = PermitLimit,
        Window = TimeSpan.FromSeconds(WindowSeconds),
        QueueLimit = QueueLimit,
        QueueProcessingOrder = QueueProcessingOrder.OldestFirst,
        AutoReplenishment = true
    };
}
