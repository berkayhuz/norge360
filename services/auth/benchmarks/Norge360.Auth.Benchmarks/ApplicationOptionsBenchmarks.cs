// <copyright file="ApplicationOptionsBenchmarks.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using BenchmarkDotNet.Attributes;
using Norge360.Auth.Application.Options;

namespace Norge360.Auth.Benchmarks;

[MemoryDiagnoser]
public class ApplicationOptionsBenchmarks
{
    [Benchmark] public AccountLifecycleOptions Create_AccountLifecycleOptions() => new();
    [Benchmark] public AuthDataProtectionOptions Create_AuthDataProtectionOptions() => new();
    [Benchmark] public AuthorizationOptions Create_AuthorizationOptions() => new();
    [Benchmark] public DatabaseOptions Create_DatabaseOptions() => new();
    [Benchmark] public DataRetentionOptions Create_DataRetentionOptions() => new();
    [Benchmark] public DistributedCacheOptions Create_DistributedCacheOptions() => new();
    [Benchmark] public IdentitySecurityOptions Create_IdentitySecurityOptions() => new();
    [Benchmark] public InvitationDeliveryOptions Create_InvitationDeliveryOptions() => new();
    [Benchmark] public JwtOptions Create_JwtOptions() => new();
    [Benchmark] public JwtSigningKeyOptions Create_JwtSigningKeyOptions() => new();
    [Benchmark] public OutboxOptions Create_OutboxOptions() => new();
    [Benchmark] public PasswordPolicyOptions Create_PasswordPolicyOptions() => new();
    [Benchmark] public SecurityAlertOptions Create_SecurityAlertOptions() => new();
    [Benchmark] public SeedOptions Create_SeedOptions() => new();
    [Benchmark] public SessionSecurityOptions Create_SessionSecurityOptions() => new();
    [Benchmark] public TenantResolutionOptions Create_TenantResolutionOptions() => new();
    [Benchmark] public TokenTransportOptions Create_TokenTransportOptions() => new();
    [Benchmark] public TokenValidationCacheOptions Create_TokenValidationCacheOptions() => new();
}
