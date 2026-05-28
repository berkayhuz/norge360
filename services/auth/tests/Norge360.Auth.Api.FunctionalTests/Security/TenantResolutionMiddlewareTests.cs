// <copyright file="TenantResolutionMiddlewareTests.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using FluentAssertions;
using MediatR;
using Moq;
using Norge360.Auth.Application.Features.Commands;
using Norge360.Auth.Application.Records;
using Norge360.Auth.Contracts.Requests;
using Norge360.Auth.Contracts.Responses;
using Norge360.Auth.TestKit.Fixtures;
using Norge360.Auth.TestKit.Helpers;

namespace Norge360.Auth.Api.FunctionalTests.Security;

[Trait("Category", "SecurityRegression")]
public sealed class TenantResolutionMiddlewareTests : IAsyncLifetime
{
    private readonly Guid _tenantId = Guid.NewGuid();
    private AuthWebApplicationFactory _factory = default!;
    private HttpClient _client = default!;

    public async Task InitializeAsync()
    {
        var overrides = TestConfiguration.CreateAuthApiDefaults();
        overrides["Security:TenantResolution:RequireResolvedTenant"] = "true";
        overrides["Security:TenantResolution:AllowBodyFallback"] = "false";
        overrides["Security:TenantResolution:TenantOptionalPathPrefixes:0"] = "/api/auth/register";
        overrides["Security:TenantResolution:TenantOptionalPathPrefixes:1"] = "/__tenant-required-test-placeholder";

        _factory = new AuthWebApplicationFactory(overrides);
        await _factory.InitializeAsync();
        _client = _factory.CreateClient();
    }

    public async Task DisposeAsync()
    {
        await _factory.DisposeAsync();
    }

    [Fact]
    public async Task Register_Should_Not_Be_Blocked_When_Tenant_Is_Not_Resolved()
    {
        _factory.SenderMock
            .Setup(sender => sender.Send(It.IsAny<RegisterCommand>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(new AuthSessionResult.Issued(new AuthenticationTokenResponse(
                "access-token",
                DateTime.UtcNow.AddMinutes(15),
                "refresh-token",
                DateTime.UtcNow.AddDays(14),
                _tenantId,
                Guid.NewGuid(),
                "berkay",
                "berkay@example.com",
                Guid.NewGuid())));

        var response = await _client.PostAsync(
            "/api/auth/register",
            JsonSerializationHelper.ToJsonContent(new RegisterRequest("Acme", "berkay", "berkay@example.com", "Str0ng!Pass123", "Berkay", "Test", "en-US")));

        response.StatusCode.Should().Be(System.Net.HttpStatusCode.OK);
    }

    [Fact]
    public async Task Tenant_Required_Endpoint_Should_Be_Blocked_When_Tenant_Is_Not_Resolved()
    {
        var response = await _client.GetAsync("/api/auth/workspaces");

        response.StatusCode.Should().Be(System.Net.HttpStatusCode.BadRequest);
    }

    [Fact]
    public async Task Login_Should_Be_Blocked_When_Tenant_Is_Not_Resolved_And_Body_Tenant_Is_Empty()
    {
        var response = await _client.PostAsync(
            "/api/auth/login",
            JsonSerializationHelper.ToJsonContent(new LoginRequest(Guid.Empty, "berkay@example.com", "Str0ng!Pass123")));

        response.StatusCode.Should().Be(System.Net.HttpStatusCode.BadRequest);
    }

    [Fact]
    public async Task Login_Should_Ignore_Tenant_Header_When_Request_Is_Not_Trusted()
    {
        using var request = new HttpRequestMessage(
            HttpMethod.Post,
            "/api/auth/login")
        {
            Content = JsonSerializationHelper.ToJsonContent(new LoginRequest(Guid.Empty, "berkay@example.com", "Str0ng!Pass123"))
        };
        request.Headers.Add("X-Tenant-Id", _tenantId.ToString("D"));

        var response = await _client.SendAsync(request);

        response.StatusCode.Should().Be(System.Net.HttpStatusCode.BadRequest);
    }

    [Fact]
    public async Task ForgotPassword_Should_Be_Blocked_When_Tenant_Is_Not_Resolved_And_Body_Tenant_Is_Empty()
    {
        var response = await _client.PostAsync(
            "/api/auth/forgot-password",
            JsonSerializationHelper.ToJsonContent(new ForgotPasswordRequest(Guid.Empty, "berkay@example.com")));

        response.StatusCode.Should().Be(System.Net.HttpStatusCode.BadRequest);
    }

    [Fact]
    public async Task ResetPassword_Should_Be_Blocked_When_Tenant_Is_Not_Resolved_And_Body_Tenant_Is_Empty()
    {
        var response = await _client.PostAsync(
            "/api/auth/reset-password",
            JsonSerializationHelper.ToJsonContent(
                new ResetPasswordRequest(Guid.Empty, Guid.NewGuid(), "reset-token", "Str0ng!Pass123")));

        response.StatusCode.Should().Be(System.Net.HttpStatusCode.BadRequest);
    }
}
