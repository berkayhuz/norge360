// <copyright file="AuthContractsBenchmarks.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using BenchmarkDotNet.Attributes;
using Norge360.Auth.Contracts.Internal;
using Norge360.Auth.Contracts.Requests;
using Norge360.Auth.Contracts.Responses;

namespace Norge360.Auth.Benchmarks;

[MemoryDiagnoser]
public class AuthContractsBenchmarks
{
    private readonly Guid _tenantId = Guid.NewGuid();
    private readonly Guid _userId = Guid.NewGuid();
    private readonly Guid _sessionId = Guid.NewGuid();
    private readonly Guid _invitationId = Guid.NewGuid();

    [Benchmark] public RegisterRequest Create_RegisterRequest() => new("Acme", "tester", "tester@example.test", "Str0ng!Pass123", "Test", "User", "en-US");
    [Benchmark] public LoginRequest Create_LoginRequest() => new(_tenantId, "tester@example.test", "Str0ng!Pass123", true, "123456", null);
    [Benchmark] public RefreshTokenRequest Create_RefreshTokenRequest() => new(_tenantId, _sessionId, "refresh-token");
    [Benchmark] public LogoutRequest Create_LogoutRequest() => new(_tenantId, _sessionId, "refresh-token");
    [Benchmark] public CreateWorkspaceRequest Create_CreateWorkspaceRequest() => new("Workspace A", "tr-TR");
    [Benchmark] public SwitchWorkspaceRequest Create_SwitchWorkspaceRequest() => new(_tenantId);
    [Benchmark] public CreateTenantInvitationRequest Create_CreateTenantInvitationRequest() => new("invitee@example.test", "Invitee", "User");
    [Benchmark] public AcceptTenantInvitationRequest Create_AcceptTenantInvitationRequest() => new(_tenantId, "token", "invitee", "invitee@example.test", "Str0ng!Pass123", "Invitee", "User");
    [Benchmark] public ConfirmEmailRequest Create_ConfirmEmailRequest() => new(_tenantId, _userId, "token");
    [Benchmark] public ConfirmEmailChangeRequest Create_ConfirmEmailChangeRequest() => new(_tenantId, _userId, "new@example.test", "token");
    [Benchmark] public ResendEmailConfirmationRequest Create_ResendEmailConfirmationRequest() => new(_tenantId, "tester@example.test");
    [Benchmark] public ResetPasswordRequest Create_ResetPasswordRequest() => new(_tenantId, _userId, "token", "N3w!Pass123");
    [Benchmark] public ForgotPasswordRequest Create_ForgotPasswordRequest() => new(_tenantId, "tester@example.test");

    [Benchmark]
    public AuthenticationTokenResponse Create_AuthenticationTokenResponse() => new(
        "access-token",
        DateTime.UtcNow.AddMinutes(15),
        "refresh-token",
        DateTime.UtcNow.AddDays(14),
        _tenantId,
        _userId,
        "tester",
        "tester@example.test",
        _sessionId,
        true);

    [Benchmark] public WorkspaceSummaryResponse Create_WorkspaceSummaryResponse() => new(_tenantId, "Workspace A", "workspace-a", "tenant-admin", true, DateTimeOffset.UtcNow);
    [Benchmark] public SessionSummaryResponse Create_SessionSummaryResponse() => new(_sessionId, true, false, "10.0.0.1", "Chrome", DateTime.UtcNow.AddDays(-2), DateTime.UtcNow, DateTime.UtcNow.AddDays(7), null, null);
    [Benchmark] public TenantInvitationResponse Create_TenantInvitationResponse() => new(_tenantId, _invitationId, "invitee@example.test", DateTime.UtcNow.AddDays(7), "pending", DateTime.UtcNow);
    [Benchmark] public TenantInvitationSummaryResponse Create_TenantInvitationSummaryResponse() => new(_tenantId, _invitationId, "invitee@example.test", "Invitee", "User", DateTime.UtcNow.AddDays(7), "pending", 1, DateTime.UtcNow.AddDays(-1), DateTime.UtcNow, null, null, "queued");
    [Benchmark] public RoleCatalogResponse Create_RoleCatalogResponse() => new("tenant-admin", 80, false, ["customers.read", "customers.write"]);
    [Benchmark] public TenantMemberResponse Create_TenantMemberResponse() => new(_tenantId, _userId, "tester", "tester@example.test", "Test", "User", true, ["tenant-admin"], ["customers.read"], DateTime.UtcNow.AddMonths(-1), DateTime.UtcNow.AddMinutes(-5));
    [Benchmark] public UserProfileResponse Create_UserProfileResponse() => new(_userId, _tenantId, "tester", "tester@example.test", true, "Test", "User", ["tenant-admin"], ["customers.read"], DateTime.UtcNow.AddMonths(-1), DateTime.UtcNow.AddMinutes(-5), DateTime.UtcNow.AddDays(-5));
    [Benchmark] public MfaStatusResult Create_MfaStatusResult() => new(true, true, 10);
    [Benchmark] public MfaSetupResult Create_MfaSetupResult() => new("ABCDEF", "otpauth://totp/Norge360");
    [Benchmark] public MfaConfirmResult Create_MfaConfirmResult() => new(true, ["A1", "B2", "C3"]);
    [Benchmark] public RecoveryCodesResult Create_RecoveryCodesResult() => new(["A1", "B2", "C3"]);
    [Benchmark] public TrustedDevicesIdentityResponse Create_TrustedDevicesIdentityResponse() => new([new TrustedDeviceIdentityResponse(Guid.NewGuid(), false, "Chrome", "10.0.0.1", "Windows", DateTimeOffset.UtcNow, DateTimeOffset.UtcNow, false)]);
}
