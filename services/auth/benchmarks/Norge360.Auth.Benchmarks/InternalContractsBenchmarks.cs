// <copyright file="InternalContractsBenchmarks.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using BenchmarkDotNet.Attributes;
using Norge360.Auth.Contracts.Internal;

namespace Norge360.Auth.Benchmarks;

[MemoryDiagnoser]
public class InternalContractsBenchmarks
{
    private readonly Guid _tenantId = Guid.NewGuid();
    private readonly Guid _userId = Guid.NewGuid();
    private readonly Guid _orgId = Guid.NewGuid();

    [Benchmark] public AccountSecuritySummaryResponse Create_AccountSecuritySummaryResponse() => new(true, DateTimeOffset.UtcNow);
    [Benchmark] public ChangePasswordIdentityRequest Create_ChangePasswordIdentityRequest() => new("Old!Pass123", "New!Pass123", true);
    [Benchmark] public ChangePasswordIdentityResult Create_ChangePasswordIdentityResult() => new(false, [new PasswordPolicyFailure("invalid_password", "Too weak.")]);
    [Benchmark] public EmailChangeConfirmIdentityRequest Create_EmailChangeConfirmIdentityRequest() => new("token");
    [Benchmark] public EmailChangeConfirmIdentityResult Create_EmailChangeConfirmIdentityResult() => new(true, "new@example.test", []);
    [Benchmark] public EmailChangeRequestIdentityRequest Create_EmailChangeRequestIdentityRequest() => new("new@example.test", "Str0ng!Pass123");
    [Benchmark] public EmailChangeRequestIdentityResult Create_EmailChangeRequestIdentityResult() => new(true, []);
    [Benchmark] public InternalCreateTenantInvitationRequest Create_InternalCreateTenantInvitationRequest() => new(_userId, "invitee@example.test", "Invitee", "User");
    [Benchmark] public InternalOrganizationMembershipSummaryResponse Create_InternalOrganizationMembershipSummaryResponse() => new(_orgId, _tenantId, "Acme", "acme", "active", true, DateTimeOffset.UtcNow.AddMonths(-1), DateTimeOffset.UtcNow, ["tenant-admin"]);
    [Benchmark] public InternalPermissionGroupResponse Create_InternalPermissionGroupResponse() => new("customers", ["customers.read", "customers.write"]);
    [Benchmark] public InternalPermissionOverviewResponse Create_InternalPermissionOverviewResponse() => new(_orgId, DateTimeOffset.UtcNow, false, ["tenant-admin"], [new InternalPermissionGroupResponse("customers", ["customers.read"])]);
    [Benchmark] public InternalUpdateTenantMemberRolesRequest Create_InternalUpdateTenantMemberRolesRequest() => new(_userId, ["tenant-user"]);
    [Benchmark] public MfaConfirmRequest Create_MfaConfirmRequest() => new("123456");
    [Benchmark] public MfaConfirmResult Create_MfaConfirmResult() => new(true, ["A1", "B2", "C3"]);
    [Benchmark] public MfaDisableRequest Create_MfaDisableRequest() => new("123456");
    [Benchmark] public MfaSetupResult Create_MfaSetupResult() => new("ABCDEF", "otpauth://totp/Norge360");
    [Benchmark] public MfaStatusResult Create_MfaStatusResult() => new(true, true, 8);
    [Benchmark] public PasswordPolicyFailure Create_PasswordPolicyFailure() => new("too_short", "Minimum length is 12.");
    [Benchmark] public RecoveryCodesResult Create_RecoveryCodesResult() => new(["A1", "B2", "C3"]);
    [Benchmark] public TrustedDeviceIdentityResponse Create_TrustedDeviceIdentityResponse() => new(Guid.NewGuid(), true, "Chrome", "10.0.0.1", "Windows", DateTimeOffset.UtcNow.AddDays(-7), DateTimeOffset.UtcNow.AddMinutes(-3), false);
    [Benchmark] public TrustedDevicesIdentityResponse Create_TrustedDevicesIdentityResponse() => new([new TrustedDeviceIdentityResponse(Guid.NewGuid(), false, "Edge", "10.0.0.2", "Windows", DateTimeOffset.UtcNow.AddDays(-3), DateTimeOffset.UtcNow, false)]);
}
