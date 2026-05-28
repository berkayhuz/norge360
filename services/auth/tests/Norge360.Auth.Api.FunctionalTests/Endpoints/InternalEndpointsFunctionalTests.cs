// <copyright file="InternalEndpointsFunctionalTests.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using System.Net.Http.Json;
using FluentAssertions;
using MediatR;
using Moq;
using Norge360.Auth.Application.Exceptions;
using Norge360.Auth.Application.Features.Commands;
using Norge360.Auth.Contracts.Internal;
using Norge360.Auth.Contracts.Responses;
using Norge360.Auth.TestKit.Extensions;
using Norge360.Auth.TestKit.Fixtures;
using Norge360.Auth.TestKit.Helpers;

namespace Norge360.Auth.Api.FunctionalTests.Endpoints;

public sealed class InternalEndpointsFunctionalTests : IAsyncLifetime
{
    private readonly Guid _tenantId = Guid.NewGuid();
    private readonly Guid _userId = Guid.NewGuid();
    private readonly Guid _sessionId = Guid.NewGuid();
    private readonly AuthWebApplicationFactory _factory;
    private HttpClient _client = default!;

    public InternalEndpointsFunctionalTests()
    {
        var overrides = TestConfiguration.CreateAuthApiDefaults();
        overrides["Security:TrustedGateway:RequireTrustedGateway"] = "true";
        overrides["Security:TrustedGateway:CurrentKeyId"] = "gateway-local-key-2026-01";
        overrides["Security:TrustedGateway:AllowedSources:0"] = "Norge360.Account";
        overrides["Security:TrustedGateway:AllowedSources:1"] = "Norge360.Gateway";
        overrides["Security:TrustedGateway:Keys:0:KeyId"] = "gateway-local-key-2026-01";
        overrides["Security:TrustedGateway:Keys:0:Secret"] = "test-gateway-key-secret-2026-abcdefghijklmnopqrstuvwxyz";
        overrides["Security:TrustedGateway:Keys:0:Enabled"] = "true";
        overrides["Security:TrustedGateway:Keys:1:KeyId"] = "account-internal-local-key-2026-01";
        overrides["Security:TrustedGateway:Keys:1:Secret"] = "test-account-key-secret-2026-abcdefghijklmnopqrstuvwxyz";
        overrides["Security:TrustedGateway:Keys:1:Enabled"] = "true";
        _factory = new AuthWebApplicationFactory(overrides);
    }

    public async Task InitializeAsync()
    {
        await _factory.InitializeAsync();
        _client = _factory.CreateAuthenticatedClient(_tenantId, _userId, _sessionId);
        _client.DefaultRequestHeaders.Add("X-Gateway-Source", "Norge360.Account");
        _client.DefaultRequestHeaders.Add("X-Tenant-Id", _tenantId.ToString("D"));
    }

    public async Task DisposeAsync()
    {
        await _factory.DisposeAsync();
    }

    [Fact]
    public async Task InternalIdentity_SecuritySummary_Should_Return_Ok()
    {
        _factory.SenderMock.Reset();
        _factory.SenderMock
            .Setup(sender => sender.Send(It.IsAny<GetAccountSecuritySummaryQuery>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(new AccountSecuritySummaryResponse(true, DateTimeOffset.UtcNow));

        var response = await _client.GetAsync($"/api/v1/internal/identity/users/{_userId:D}/security-summary");

        response.StatusCode.Should().Be(System.Net.HttpStatusCode.OK);
    }

    [Fact]
    public async Task InternalIdentity_ChangePassword_Should_Return_Ok_With_Failures_On_ClientError()
    {
        _factory.SenderMock.Reset();
        _factory.SenderMock
            .Setup(sender => sender.Send(It.IsAny<ChangePasswordCommand>(), It.IsAny<CancellationToken>()))
            .ThrowsAsync(new AuthApplicationException(
                "Invalid password",
                "Current password is invalid.",
                StatusCodes.Status400BadRequest,
                errorCode: "invalid_current_password"));

        var response = await _client.PostAsync(
            $"/api/v1/internal/identity/users/{_userId:D}/password/change",
            JsonSerializationHelper.ToJsonContent(new ChangePasswordIdentityRequest("old", "new", true)));

        response.StatusCode.Should().Be(System.Net.HttpStatusCode.OK);
        var payload = await response.Content.ReadFromJsonAsync<ChangePasswordIdentityResult>();
        payload.Should().NotBeNull();
        payload!.Succeeded.Should().BeFalse();
        payload.Failures.Should().ContainSingle(f => f.Code == "invalid_current_password");
    }

    [Fact]
    public async Task InternalIdentity_RevokeTrustedDevice_Should_Return_NotFound_When_NotRevoked()
    {
        var deviceId = Guid.NewGuid();
        _factory.SenderMock.Reset();
        _factory.SenderMock
            .Setup(sender => sender.Send(It.IsAny<RevokeTrustedDeviceCommand>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(false);

        var response = await _client.DeleteAsync($"/api/v1/internal/identity/users/{_userId:D}/trusted-devices/{deviceId:D}");

        response.StatusCode.Should().Be(System.Net.HttpStatusCode.NotFound);
    }

    [Fact]
    public async Task InternalMembership_Organizations_Should_Return_Ok()
    {
        _factory.SenderMock.Reset();
        _factory.SenderMock
            .Setup(sender => sender.Send(It.IsAny<ListUserWorkspaceMembershipsCommand>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(
            [
                new InternalOrganizationMembershipSummaryResponse(
                    Guid.NewGuid(),
                    _tenantId,
                    "Acme",
                    "acme",
                    "active",
                    true,
                    DateTimeOffset.UtcNow,
                    DateTimeOffset.UtcNow,
                    ["owner"])
            ]);

        var response = await _client.GetAsync($"/api/v1/internal/membership/users/{_userId:D}/organizations");

        response.StatusCode.Should().Be(System.Net.HttpStatusCode.OK);
    }

    [Fact]
    public async Task InternalMembership_Permissions_Should_Return_Ok()
    {
        _factory.SenderMock.Reset();
        _factory.SenderMock
            .Setup(sender => sender.Send(It.IsAny<GetUserWorkspacePermissionsCommand>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(new InternalPermissionOverviewResponse(
                Guid.NewGuid(),
                DateTimeOffset.UtcNow,
                false,
                ["owner"],
                [new InternalPermissionGroupResponse("customers", ["customers.read"])]));

        var response = await _client.GetAsync($"/api/v1/internal/membership/users/{_userId:D}/permissions?organizationId={Guid.NewGuid():D}");

        response.StatusCode.Should().Be(System.Net.HttpStatusCode.OK);
    }

    [Fact]
    public async Task InternalAccountManagement_CreateInvitation_Should_Return_Ok()
    {
        _factory.SenderMock.Reset();
        _factory.SenderMock
            .Setup(sender => sender.Send(It.IsAny<CreateTenantInvitationCommand>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(new TenantInvitationResponse(_tenantId, Guid.NewGuid(), "invitee@example.com", DateTime.UtcNow.AddDays(7), "pending", DateTime.UtcNow));

        var response = await _client.PostAsync(
            "/api/v1/internal/account-management/invitations",
            JsonSerializationHelper.ToJsonContent(new InternalCreateTenantInvitationRequest(_userId, "invitee@example.com", "Invitee", "Test")));

        response.StatusCode.Should().Be(System.Net.HttpStatusCode.OK);
    }

    [Fact]
    public async Task InternalAccountManagement_ListMembers_Should_Return_Ok()
    {
        _factory.SenderMock.Reset();
        _factory.SenderMock
            .Setup(sender => sender.Send(It.IsAny<ListTenantMembersCommand>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(
            [
                new TenantMemberResponse(
                    _tenantId,
                    _userId,
                    "tester",
                    "tester@example.com",
                    "Test",
                    "User",
                    true,
                    ["owner"],
                    ["customers.read"],
                    DateTime.UtcNow.AddDays(-10),
                    DateTime.UtcNow)
            ]);

        var response = await _client.GetAsync($"/api/v1/internal/account-management/members?actorUserId={_userId:D}");

        response.StatusCode.Should().Be(System.Net.HttpStatusCode.OK);
    }

    [Fact]
    public async Task InternalIdentity_Should_Return_Forbidden_When_Source_Is_Not_Allowed()
    {
        using var unauthorizedSourceClient = _factory.CreateAuthenticatedClient(_tenantId, _userId, _sessionId);
        unauthorizedSourceClient.DefaultRequestHeaders.Add("X-Gateway-Source", "Unknown.Source");
        unauthorizedSourceClient.DefaultRequestHeaders.Add("X-Tenant-Id", _tenantId.ToString("D"));

        var response = await unauthorizedSourceClient.GetAsync($"/api/v1/internal/identity/users/{_userId:D}/security-summary");

        response.StatusCode.Should().Be(System.Net.HttpStatusCode.Forbidden);
    }
}
