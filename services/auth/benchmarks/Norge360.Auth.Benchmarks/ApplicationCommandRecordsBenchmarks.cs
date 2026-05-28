// <copyright file="ApplicationCommandRecordsBenchmarks.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using BenchmarkDotNet.Attributes;
using Norge360.Auth.Application.Features.Commands;

namespace Norge360.Auth.Benchmarks;

[MemoryDiagnoser]
public class ApplicationCommandRecordsBenchmarks
{
    private readonly Guid _tenantId = Guid.NewGuid();
    private readonly Guid _targetTenantId = Guid.NewGuid();
    private readonly Guid _userId = Guid.NewGuid();
    private readonly Guid _sessionId = Guid.NewGuid();
    private readonly Guid _targetSessionId = Guid.NewGuid();
    private readonly Guid _deviceId = Guid.NewGuid();
    private readonly Guid _invitationId = Guid.NewGuid();

    [Benchmark] public RegisterCommand Create_RegisterCommand() => new("Acme", "tester", "tester@example.test", "Str0ng!Pass123", "Test", "User", "en-US", "10.0.0.1", "Chrome");
    [Benchmark] public LoginCommand Create_LoginCommand() => new(_tenantId, "tester@example.test", "Str0ng!Pass123", true, "123456", null, "10.0.0.1", "Chrome");
    [Benchmark] public LogoutCommand Create_LogoutCommand() => new(_tenantId, _sessionId, "refresh-token");
    [Benchmark] public RefreshTokenCommand Create_RefreshTokenCommand() => new(_tenantId, _sessionId, "refresh-token", "10.0.0.1", "Chrome");
    [Benchmark] public ForgotPasswordCommand Create_ForgotPasswordCommand() => new(_tenantId, "tester@example.test", "10.0.0.1", "Chrome", "corr-1", "trace-1");
    [Benchmark] public ResetPasswordCommand Create_ResetPasswordCommand() => new(_tenantId, _userId, "token", "N3w!Pass123", "10.0.0.1", "Chrome", "corr-1", "trace-1");
    [Benchmark] public ConfirmEmailCommand Create_ConfirmEmailCommand() => new(_tenantId, _userId, "token", "10.0.0.1", "Chrome", "corr-1", "trace-1");
    [Benchmark] public ResendEmailConfirmationCommand Create_ResendEmailConfirmationCommand() => new(_tenantId, "tester@example.test", "10.0.0.1", "Chrome", "corr-1", "trace-1");
    [Benchmark] public ChangePasswordCommand Create_ChangePasswordCommand() => new(_tenantId, _userId, "Old!Pass123", "New!Pass123", true, _sessionId, "10.0.0.1", "Chrome", "corr-1", "trace-1");
    [Benchmark] public ChangeEmailCommand Create_ChangeEmailCommand() => new(_tenantId, _userId, "new@example.test", "old@example.test", "Str0ng!Pass123", "10.0.0.1", "Chrome", "corr-1", "trace-1");
    [Benchmark] public ConfirmEmailChangeCommand Create_ConfirmEmailChangeCommand() => new(_tenantId, _userId, "new@example.test", "token", "10.0.0.1", "Chrome", "corr-1", "trace-1");
    [Benchmark] public GetUserProfileCommand Create_GetUserProfileCommand() => new(_tenantId, _userId);
    [Benchmark] public UpdateProfileCommand Create_UpdateProfileCommand() => new(_tenantId, _userId, "Test", "User");
    [Benchmark] public RevokeSessionCommand Create_RevokeSessionCommand() => new(_tenantId, _userId, _sessionId, _targetSessionId, "tester@example.test", "10.0.0.1", "Chrome", "corr-1", "trace-1");
    [Benchmark] public RevokeOtherSessionsCommand Create_RevokeOtherSessionsCommand() => new(_tenantId, _userId, _sessionId, "tester@example.test", "10.0.0.1", "Chrome", "corr-1", "trace-1");

    [Benchmark] public CreateWorkspaceCommand Create_CreateWorkspaceCommand() => new(_tenantId, _userId, "Workspace A", "tr-TR", "10.0.0.1", "Chrome", "corr-1", "trace-1");
    [Benchmark] public SwitchWorkspaceCommand Create_SwitchWorkspaceCommand() => new(_tenantId, _targetTenantId, _userId, "10.0.0.1", "Chrome", "corr-1", "trace-1");
    [Benchmark] public DeleteWorkspaceCommand Create_DeleteWorkspaceCommand() => new(_tenantId, _targetTenantId, _userId, "10.0.0.1", "Chrome", "corr-1", "trace-1");
    [Benchmark] public ListUserWorkspaceMembershipsCommand Create_ListUserWorkspaceMembershipsCommand() => new(_tenantId, _userId);
    [Benchmark] public GetUserWorkspacePermissionsCommand Create_GetUserWorkspacePermissionsCommand() => new(_tenantId, _userId, Guid.NewGuid());

    [Benchmark] public CreateTenantInvitationCommand Create_CreateTenantInvitationCommand() => new(_tenantId, _userId, "invitee@example.test", "Invitee", "User", "10.0.0.1", "Chrome", "corr-1", "trace-1");
    [Benchmark] public ListTenantInvitationsCommand Create_ListTenantInvitationsCommand() => new(_tenantId, _userId);
    [Benchmark] public ResendTenantInvitationCommand Create_ResendTenantInvitationCommand() => new(_tenantId, _invitationId, _userId, "10.0.0.1", "Chrome", "corr-1", "trace-1");
    [Benchmark] public RevokeTenantInvitationCommand Create_RevokeTenantInvitationCommand() => new(_tenantId, _invitationId, _userId, "10.0.0.1", "Chrome", "corr-1", "trace-1");
    [Benchmark] public AcceptTenantInvitationCommand Create_AcceptTenantInvitationCommand() => new(_tenantId, "token", "invitee", "invitee@example.test", "Str0ng!Pass123", "Invitee", "User", "10.0.0.1", "Chrome", "corr-1", "trace-1");

    [Benchmark] public ListTenantMembersCommand Create_ListTenantMembersCommand() => new(_tenantId, _userId);
    [Benchmark] public UpdateTenantMemberRolesCommand Create_UpdateTenantMemberRolesCommand() => new(_tenantId, _userId, Guid.NewGuid(), new[] { "tenant-admin", "tenant-user" }, "10.0.0.1", "Chrome", "corr-1", "trace-1");
    [Benchmark] public ListRoleCatalogCommand Create_ListRoleCatalogCommand() => new(_tenantId, _userId);

    [Benchmark] public GetAccountSecuritySummaryQuery Create_GetAccountSecuritySummaryQuery() => new(_tenantId, _userId);
    [Benchmark] public GetMfaStatusQuery Create_GetMfaStatusQuery() => new(_tenantId, _userId);
    [Benchmark] public SetupMfaCommand Create_SetupMfaCommand() => new(_tenantId, _userId, "https://auth.norge360.test");
    [Benchmark] public ConfirmMfaCommand Create_ConfirmMfaCommand() => new(_tenantId, _userId, "123456", "10.0.0.1", "Chrome", "corr-1", "trace-1");
    [Benchmark] public DisableMfaCommand Create_DisableMfaCommand() => new(_tenantId, _userId, "123456", "10.0.0.1", "Chrome", "corr-1", "trace-1");
    [Benchmark] public RegenerateRecoveryCodesCommand Create_RegenerateRecoveryCodesCommand() => new(_tenantId, _userId, "10.0.0.1", "Chrome", "corr-1", "trace-1");
    [Benchmark] public ListTrustedDevicesQuery Create_ListTrustedDevicesQuery() => new(_tenantId, _userId, _sessionId);
    [Benchmark] public RevokeTrustedDeviceCommand Create_RevokeTrustedDeviceCommand() => new(_tenantId, _userId, _deviceId, "10.0.0.1", "Chrome", "corr-1", "trace-1");
    [Benchmark] public ConfirmEmailChangeForAccountCommand Create_ConfirmEmailChangeForAccountCommand() => new(_tenantId, _userId, "token", "10.0.0.1", "Chrome", "corr-1", "trace-1");
}
