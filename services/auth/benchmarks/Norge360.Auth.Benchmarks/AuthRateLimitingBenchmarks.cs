// <copyright file="AuthRateLimitingBenchmarks.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using BenchmarkDotNet.Attributes;
using Norge360.Auth.API.Security;

namespace Norge360.Auth.Benchmarks;

[MemoryDiagnoser]
public class AuthRateLimitingBenchmarks
{
    private AuthRateLimitingOptions _options = default!;

    [GlobalSetup]
    public void Setup()
    {
        _options = new AuthRateLimitingOptions();
    }

    [Benchmark] public object Global_ToLimiterOptions() => _options.Global.ToLimiterOptions();
    [Benchmark] public object Login_ToLimiterOptions() => _options.Login.ToLimiterOptions();
    [Benchmark] public object Register_ToLimiterOptions() => _options.Register.ToLimiterOptions();
    [Benchmark] public object Refresh_ToLimiterOptions() => _options.Refresh.ToLimiterOptions();
    [Benchmark] public object Logout_ToLimiterOptions() => _options.Logout.ToLimiterOptions();
    [Benchmark] public object Invite_ToLimiterOptions() => _options.Invite.ToLimiterOptions();
    [Benchmark] public object RoleManagement_ToLimiterOptions() => _options.RoleManagement.ToLimiterOptions();
    [Benchmark] public object PasswordRecovery_ToLimiterOptions() => _options.PasswordRecovery.ToLimiterOptions();
    [Benchmark] public object EmailConfirmation_ToLimiterOptions() => _options.EmailConfirmation.ToLimiterOptions();
    [Benchmark] public FixedWindowRuleOptions Create_CustomRule() => new(42, 15, 4);
}
