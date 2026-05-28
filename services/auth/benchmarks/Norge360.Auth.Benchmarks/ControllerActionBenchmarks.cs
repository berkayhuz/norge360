// <copyright file="ControllerActionBenchmarks.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using System.Security.Claims;
using System.IdentityModel.Tokens.Jwt;
using BenchmarkDotNet.Attributes;
using MediatR;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Options;
using Norge360.AspNetCore.TrustedGateway.Options;
using Norge360.Auth.API.Accessors;
using Norge360.Auth.API.Controllers;
using Norge360.Auth.API.Cookies;
using Norge360.Auth.API.Security;
using Norge360.Auth.Application.Abstractions;
using Norge360.Auth.Application.Features.Commands;
using Norge360.Auth.Application.Options;
using Norge360.Auth.Application.Records;
using Norge360.Auth.Application.Security;
using Norge360.Auth.Contracts.Internal;
using Norge360.Auth.Contracts.Requests;
using Norge360.Auth.Contracts.Responses;

namespace Norge360.Auth.Benchmarks;

[MemoryDiagnoser]
public class ControllerActionBenchmarks
{
    private AuthController _authController = default!;
    private InternalIdentityController _internalIdentityController = default!;
    private InternalMembershipController _internalMembershipController = default!;
    private InternalAccountManagementController _internalAccountManagementController = default!;

    private RegisterRequest _registerRequest = default!;
    private LoginRequest _loginRequest = default!;
    private ForgotPasswordRequest _forgotPasswordRequest = default!;
    private ResetPasswordRequest _resetPasswordRequest = default!;
    private ConfirmEmailRequest _confirmEmailRequest = default!;
    private CreateWorkspaceRequest _createWorkspaceRequest = default!;
    private SwitchWorkspaceRequest _switchWorkspaceRequest = default!;
    private AcceptTenantInvitationRequest _acceptInvitationRequest = default!;
    private ResendEmailConfirmationRequest _resendEmailConfirmationRequest = default!;
    private ConfirmEmailChangeRequest _confirmEmailChangeRequest = default!;
    private RefreshTokenRequest _refreshTokenRequest = default!;
    private LogoutRequest _logoutRequest = default!;
    private InternalCreateTenantInvitationRequest _internalInvitationRequest = default!;
    private MfaConfirmRequest _mfaConfirmRequest = default!;
    private MfaDisableRequest _mfaDisableRequest = default!;
    private EmailChangeRequestIdentityRequest _emailChangeRequest = default!;
    private EmailChangeConfirmIdentityRequest _emailChangeConfirmRequest = default!;
    private InternalUpdateTenantMemberRolesRequest _updateRolesRequest = default!;
    private Guid _tenantId;
    private Guid _userId;
    private Guid _sessionId;
    private Guid _invitationId;
    private Guid _deviceId;

    [GlobalSetup]
    public void Setup()
    {
        _tenantId = Guid.NewGuid();
        _userId = Guid.NewGuid();
        _sessionId = Guid.NewGuid();

        _registerRequest = new RegisterRequest("Acme", "tester", "tester@example.test", "Str0ng!Pass123", "Test", "User", "en-US");
        _loginRequest = new LoginRequest(_tenantId, "tester@example.test", "Str0ng!Pass123");
        _forgotPasswordRequest = new ForgotPasswordRequest(_tenantId, "tester@example.test");
        _resetPasswordRequest = new ResetPasswordRequest(_tenantId, _userId, "token", "Str0ng!Pass123");
        _confirmEmailRequest = new ConfirmEmailRequest(_tenantId, _userId, "token");
        _createWorkspaceRequest = new CreateWorkspaceRequest("Workspace A", "en-US");
        _switchWorkspaceRequest = new SwitchWorkspaceRequest(Guid.NewGuid());
        _acceptInvitationRequest = new AcceptTenantInvitationRequest(_tenantId, "token", "invitee", "invitee@example.test", "Str0ng!Pass123", "Invitee", "Test");
        _resendEmailConfirmationRequest = new ResendEmailConfirmationRequest(_tenantId, "tester@example.test");
        _confirmEmailChangeRequest = new ConfirmEmailChangeRequest(_tenantId, _userId, "new@example.test", "token");
        _refreshTokenRequest = new RefreshTokenRequest(_tenantId, _sessionId, "refresh-token");
        _logoutRequest = new LogoutRequest(_tenantId, _sessionId, "refresh-token");
        _internalInvitationRequest = new InternalCreateTenantInvitationRequest(_userId, "invitee@example.test", "Invitee", "Test");
        _mfaConfirmRequest = new MfaConfirmRequest("123456");
        _mfaDisableRequest = new MfaDisableRequest("123456");
        _emailChangeRequest = new EmailChangeRequestIdentityRequest("new@example.test", "Str0ng!Pass123");
        _emailChangeConfirmRequest = new EmailChangeConfirmIdentityRequest("token");
        _updateRolesRequest = new InternalUpdateTenantMemberRolesRequest(_userId, ["tenant-admin"]);
        _invitationId = Guid.NewGuid();
        _deviceId = Guid.NewGuid();

        var tokenOptions = new TokenTransportOptions
        {
            Mode = TokenTransportModes.CookiesOnly,
            AllowRefreshTokenFromRequestBody = true,
            AllowSessionIdFromRequestBody = true
        };
        var cookieService = new AuthCookieService(Options.Create(tokenOptions));
        var trustedAccessor = new AuthRequestContextAccessor(
            new StaticTenantContextAccessor(new TenantContext(_tenantId, null, "header", true)),
            Options.Create(new TenantResolutionOptions { AllowBodyFallback = true }),
            Options.Create(tokenOptions),
            cookieService);

        var sender = new BenchmarkSender(_tenantId, _userId, _sessionId);
        _authController = new AuthController(sender, trustedAccessor, cookieService);
        _internalIdentityController = new InternalIdentityController(
            sender,
            trustedAccessor,
            Options.Create(new JwtOptions { Issuer = "https://auth.norge360.test" }),
            Options.Create(new InternalIdentityOptions { AllowedSources = ["Norge360.Account"] }),
            Options.Create(new TrustedGatewayOptions { SourceHeaderName = "X-Gateway-Source" }));
        _internalMembershipController = new InternalMembershipController(
            sender,
            trustedAccessor,
            Options.Create(new InternalIdentityOptions { AllowedSources = ["Norge360.Account"] }),
            Options.Create(new TrustedGatewayOptions { SourceHeaderName = "X-Gateway-Source" }));
        _internalAccountManagementController = new InternalAccountManagementController(
            sender,
            trustedAccessor,
            Options.Create(new InternalIdentityOptions { AllowedSources = ["Norge360.Account"] }),
            Options.Create(new TrustedGatewayOptions { SourceHeaderName = "X-Gateway-Source" }));

        ConfigureControllerContext(_authController, authenticated: true);
        ConfigureInternalControllerContext(_internalIdentityController);
        ConfigureInternalControllerContext(_internalMembershipController);
        ConfigureInternalControllerContext(_internalAccountManagementController);
    }

    [Benchmark] public Task<IActionResult> Auth_Register() => _authController.Register(_registerRequest, CancellationToken.None);
    [Benchmark] public Task<IActionResult> Auth_Login() => _authController.Login(_loginRequest, CancellationToken.None);
    [Benchmark] public Task<IActionResult> Auth_ForgotPassword() => _authController.ForgotPassword(_forgotPasswordRequest, CancellationToken.None);
    [Benchmark] public Task<IActionResult> Auth_ResetPassword() => _authController.ResetPassword(_resetPasswordRequest, CancellationToken.None);
    [Benchmark] public Task<IActionResult> Auth_ConfirmEmail() => _authController.ConfirmEmail(_confirmEmailRequest, CancellationToken.None);
    [Benchmark] public Task<IActionResult> Auth_ResendConfirmEmail() => _authController.ResendConfirmEmail(_resendEmailConfirmationRequest, CancellationToken.None);
    [Benchmark] public Task<IActionResult> Auth_ConfirmEmailChange() => _authController.ConfirmEmailChange(_confirmEmailChangeRequest, CancellationToken.None);
    [Benchmark] public Task<IActionResult> Auth_CreateWorkspace() => _authController.CreateWorkspace(_createWorkspaceRequest, CancellationToken.None);
    [Benchmark] public Task<IActionResult> Auth_DeleteWorkspace() => _authController.DeleteWorkspace(_switchWorkspaceRequest.TenantId, CancellationToken.None);
    [Benchmark] public Task<ActionResult<IReadOnlyCollection<WorkspaceSummaryResponse>>> Auth_ListWorkspaces() => _authController.ListWorkspaces(CancellationToken.None);
    [Benchmark] public Task<IActionResult> Auth_SwitchWorkspace() => _authController.SwitchWorkspace(_switchWorkspaceRequest, CancellationToken.None);
    [Benchmark] public Task<IActionResult> Auth_AcceptInvitation() => _authController.AcceptInvitation(_acceptInvitationRequest, CancellationToken.None);
    [Benchmark] public Task<IActionResult> Auth_Refresh() => _authController.Refresh(_refreshTokenRequest, CancellationToken.None);
    [Benchmark] public Task<IActionResult> Auth_Logout() => _authController.Logout(_logoutRequest, CancellationToken.None);
    [Benchmark] public IActionResult Auth_SessionStatus() => _authController.GetSessionStatus();
    [Benchmark] public Task<ActionResult<AccountSecuritySummaryResponse>> InternalIdentity_GetSecuritySummary() => _internalIdentityController.GetSecuritySummary(_userId, CancellationToken.None);
    [Benchmark] public Task<ActionResult<ChangePasswordIdentityResult>> InternalIdentity_ChangePassword() => _internalIdentityController.ChangePassword(_userId, new ChangePasswordIdentityRequest("old", "new", true), CancellationToken.None);
    [Benchmark] public Task<ActionResult<MfaStatusResult>> InternalIdentity_GetMfa() => _internalIdentityController.GetMfa(_userId, CancellationToken.None);
    [Benchmark] public Task<ActionResult<MfaSetupResult>> InternalIdentity_SetupMfa() => _internalIdentityController.SetupMfa(_userId, CancellationToken.None);
    [Benchmark] public Task<ActionResult<MfaConfirmResult>> InternalIdentity_ConfirmMfa() => _internalIdentityController.ConfirmMfa(_userId, _mfaConfirmRequest, CancellationToken.None);
    [Benchmark] public Task<IActionResult> InternalIdentity_DisableMfa() => _internalIdentityController.DisableMfa(_userId, _mfaDisableRequest, CancellationToken.None);
    [Benchmark] public Task<ActionResult<RecoveryCodesResult>> InternalIdentity_RegenerateRecoveryCodes() => _internalIdentityController.RegenerateRecoveryCodes(_userId, CancellationToken.None);
    [Benchmark] public Task<ActionResult<EmailChangeRequestIdentityResult>> InternalIdentity_RequestEmailChange() => _internalIdentityController.RequestEmailChange(_userId, _emailChangeRequest, CancellationToken.None);
    [Benchmark] public Task<ActionResult<EmailChangeConfirmIdentityResult>> InternalIdentity_ConfirmEmailChange() => _internalIdentityController.ConfirmEmailChange(_userId, _emailChangeConfirmRequest, CancellationToken.None);
    [Benchmark] public Task<ActionResult<TrustedDevicesIdentityResponse>> InternalIdentity_GetTrustedDevices() => _internalIdentityController.GetTrustedDevices(_userId, CancellationToken.None);
    [Benchmark] public Task<IActionResult> InternalIdentity_RevokeTrustedDevice() => _internalIdentityController.RevokeTrustedDevice(_userId, _deviceId, CancellationToken.None);
    [Benchmark] public Task<ActionResult<IReadOnlyCollection<InternalOrganizationMembershipSummaryResponse>>> InternalMembership_ListOrganizations() => _internalMembershipController.ListOrganizations(_userId, CancellationToken.None);
    [Benchmark] public Task<ActionResult<InternalPermissionOverviewResponse>> InternalMembership_GetPermissions() => _internalMembershipController.GetPermissions(_userId, Guid.NewGuid(), CancellationToken.None);
    [Benchmark] public Task<ActionResult<TenantInvitationResponse>> InternalAccountManagement_CreateInvitation() => _internalAccountManagementController.CreateInvitation(_internalInvitationRequest, CancellationToken.None);
    [Benchmark] public Task<ActionResult<IReadOnlyCollection<TenantInvitationSummaryResponse>>> InternalAccountManagement_ListInvitations() => _internalAccountManagementController.ListInvitations(_userId, CancellationToken.None);
    [Benchmark] public Task<ActionResult<TenantInvitationResponse>> InternalAccountManagement_ResendInvitation() => _internalAccountManagementController.ResendInvitation(_invitationId, _userId, CancellationToken.None);
    [Benchmark] public Task<ActionResult<TenantInvitationResponse>> InternalAccountManagement_RevokeInvitation() => _internalAccountManagementController.RevokeInvitation(_invitationId, _userId, CancellationToken.None);
    [Benchmark] public Task<ActionResult<IReadOnlyCollection<TenantMemberResponse>>> InternalAccountManagement_ListMembers() => _internalAccountManagementController.ListMembers(_userId, CancellationToken.None);
    [Benchmark] public Task<ActionResult<IReadOnlyCollection<RoleCatalogResponse>>> InternalAccountManagement_ListRoleCatalog() => _internalAccountManagementController.ListRoleCatalog(_userId, CancellationToken.None);
    [Benchmark] public Task<ActionResult<TenantMemberResponse>> InternalAccountManagement_UpdateMemberRoles() => _internalAccountManagementController.UpdateMemberRoles(_userId, _updateRolesRequest, CancellationToken.None);

    private void ConfigureControllerContext(ControllerBase controller, bool authenticated)
    {
        var context = new DefaultHttpContext();
        context.Request.Scheme = "https";
        context.Request.Headers.UserAgent = "bench-agent";
        context.Request.Headers.Cookie = $"__Secure-Norge360-refresh=refresh-token; __Secure-Norge360-session={_sessionId:D}";
        controller.ControllerContext = new ControllerContext { HttpContext = context };
        if (authenticated)
        {
            controller.ControllerContext.HttpContext.User = new ClaimsPrincipal(new ClaimsIdentity(
            [
                new Claim("tenant_id", _tenantId.ToString("D")),
                new Claim(ClaimTypes.NameIdentifier, _userId.ToString("D")),
                new Claim(JwtRegisteredClaimNames.Sid, _sessionId.ToString("D")),
                new Claim(ClaimTypes.Email, "tester@example.test"),
                new Claim("permission", "customers.read")
            ], "bench"));
        }
    }

    private void ConfigureInternalControllerContext(ControllerBase controller)
    {
        var context = new DefaultHttpContext();
        context.Request.Scheme = "https";
        context.Request.Headers.UserAgent = "bench-agent";
        context.Request.Headers["X-Gateway-Source"] = "Norge360.Account";
        controller.ControllerContext = new ControllerContext { HttpContext = context };
    }

    private sealed class StaticTenantContextAccessor(TenantContext? current) : ITenantContextAccessor
    {
        public TenantContext? Current => current;
    }

    private sealed class BenchmarkSender(Guid tenantId, Guid userId, Guid sessionId) : ISender
    {
        private static AuthenticationTokenResponse CreateToken(Guid tenant, Guid user, Guid session) =>
            new(
                "access-token",
                DateTime.UtcNow.AddMinutes(15),
                "refresh-token",
                DateTime.UtcNow.AddDays(14),
                tenant,
                user,
                "tester",
                "tester@example.test",
                session,
                IsPersistent: true);

        public Task<TResponse> Send<TResponse>(IRequest<TResponse> request, CancellationToken cancellationToken = default)
        {
            object response = request switch
            {
                RegisterCommand => new AuthSessionResult.Issued(CreateToken(tenantId, userId, sessionId)),
                LoginCommand => CreateToken(tenantId, userId, sessionId),
                ForgotPasswordCommand => Unit.Value,
                ResetPasswordCommand => Unit.Value,
                ConfirmEmailCommand => Unit.Value,
                ResendEmailConfirmationCommand => Unit.Value,
                ConfirmEmailChangeCommand => Unit.Value,
                CreateWorkspaceCommand => CreateToken(tenantId, userId, sessionId),
                SwitchWorkspaceCommand => CreateToken(tenantId, userId, sessionId),
                DeleteWorkspaceCommand => Unit.Value,
                AcceptTenantInvitationCommand => new AuthSessionResult.Issued(CreateToken(tenantId, userId, sessionId)),
                RefreshTokenCommand => CreateToken(tenantId, userId, sessionId),
                LogoutCommand => Unit.Value,
                GetAccountSecuritySummaryQuery => new AccountSecuritySummaryResponse(true, DateTimeOffset.UtcNow),
                ChangePasswordCommand => Unit.Value,
                GetMfaStatusQuery => new MfaStatusResult(true, true, 8),
                SetupMfaCommand => new MfaSetupResult("SECRET", "otpauth://totp/Norge360"),
                ConfirmMfaCommand => new MfaConfirmResult(true, ["AAA-BBB", "CCC-DDD"]),
                DisableMfaCommand => Unit.Value,
                RegenerateRecoveryCodesCommand => new RecoveryCodesResult(["AAA-BBB", "CCC-DDD"]),
                ChangeEmailCommand => Unit.Value,
                ConfirmEmailChangeForAccountCommand => new EmailChangeConfirmIdentityResult(true, "new@example.test", []),
                ListTrustedDevicesQuery => new TrustedDevicesIdentityResponse(
                    [new TrustedDeviceIdentityResponse(Guid.NewGuid(), false, "Chrome", "10.10.0.10", "Windows", DateTimeOffset.UtcNow, DateTimeOffset.UtcNow, false)]),
                RevokeTrustedDeviceCommand => true,
                ListUserWorkspaceMembershipsCommand => new InternalOrganizationMembershipSummaryResponse[]
                {
                    new(
                        Guid.NewGuid(),
                        tenantId,
                        "Workspace A",
                        "workspace-a",
                        "active",
                        true,
                        DateTimeOffset.UtcNow.AddDays(-30),
                        DateTimeOffset.UtcNow,
                        new[] { AuthorizationCatalog.Roles.TenantAdmin })
                },
                GetUserWorkspacePermissionsCommand => new InternalPermissionOverviewResponse(
                    Guid.NewGuid(),
                    DateTimeOffset.UtcNow,
                    false,
                    ["owner"],
                    [new InternalPermissionGroupResponse("customers", ["customers.read"])]),
                CreateTenantInvitationCommand => new TenantInvitationResponse(tenantId, Guid.NewGuid(), "invitee@example.test", DateTime.UtcNow.AddDays(7), "pending", DateTime.UtcNow),
                ListTenantInvitationsCommand => Array.Empty<TenantInvitationSummaryResponse>(),
                ResendTenantInvitationCommand => new TenantInvitationResponse(tenantId, Guid.NewGuid(), "invitee@example.test", DateTime.UtcNow.AddDays(7), "pending", DateTime.UtcNow),
                RevokeTenantInvitationCommand => new TenantInvitationResponse(tenantId, Guid.NewGuid(), "invitee@example.test", DateTime.UtcNow.AddDays(7), "revoked", DateTime.UtcNow),
                ListTenantMembersCommand => Array.Empty<TenantMemberResponse>(),
                ListRoleCatalogCommand => Array.Empty<RoleCatalogResponse>(),
                UpdateTenantMemberRolesCommand => new TenantMemberResponse(
                    tenantId,
                    Guid.NewGuid(),
                    "tester",
                    "tester@example.test",
                    "Test",
                    "User",
                    true,
                    ["tenant-admin"],
                    ["customers.read"],
                    DateTime.UtcNow.AddDays(-10),
                    DateTime.UtcNow),
                _ => throw new NotSupportedException($"Request type not supported in benchmark sender: {request.GetType().Name}")
            };

            return Task.FromResult((TResponse)response);
        }

        public Task<object?> Send(object request, CancellationToken cancellationToken = default) =>
            throw new NotSupportedException();

        Task ISender.Send<TRequest>(TRequest request, CancellationToken cancellationToken) =>
            throw new NotSupportedException();

        public IAsyncEnumerable<TResponse> CreateStream<TResponse>(IStreamRequest<TResponse> request, CancellationToken cancellationToken = default) =>
            throw new NotSupportedException();

        public IAsyncEnumerable<object?> CreateStream(object request, CancellationToken cancellationToken = default) =>
            throw new NotSupportedException();
    }
}
