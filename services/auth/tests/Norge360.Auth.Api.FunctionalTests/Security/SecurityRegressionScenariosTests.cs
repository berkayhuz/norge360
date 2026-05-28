// <copyright file="SecurityRegressionScenariosTests.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using FluentAssertions;
using Moq;
using Norge360.Auth.Application.Exceptions;
using Norge360.Auth.Application.Features.Commands;
using Norge360.Auth.Contracts.Requests;
using Norge360.Auth.TestKit.Extensions;
using Norge360.Auth.TestKit.Fixtures;
using Norge360.Auth.TestKit.Helpers;

namespace Norge360.Auth.Api.FunctionalTests.Security;

[Trait("Category", "SecurityRegression")]
public sealed class SecurityRegressionScenariosTests : IAsyncLifetime
{
    private readonly AuthWebApplicationFactory _factory = new();
    private HttpClient _client = default!;

    public async Task InitializeAsync()
    {
        await _factory.InitializeAsync();
        _client = _factory.CreateClient();
    }

    public async Task DisposeAsync()
    {
        await _factory.DisposeAsync();
    }

    [Fact]
    public async Task MfaEnabledUser_Should_Not_Get_Token_Without_Second_Factor()
    {
        _factory.SenderMock.Reset();
        _factory.SenderMock
            .Setup(sender => sender.Send(It.IsAny<LoginCommand>(), It.IsAny<CancellationToken>()))
            .ThrowsAsync(new AuthApplicationException(
                "Second factor required",
                "Multi-factor authentication challenge is required for this account.",
                StatusCodes.Status401Unauthorized,
                errorCode: "mfa_required"));

        var response = await _client.PostAsync(
            "/api/auth/login",
            JsonSerializationHelper.ToJsonContent(new LoginRequest(Guid.NewGuid(), "jane@example.com", "Password123!")));

        var problem = await response.ShouldBeProblemDetailsAsync(StatusCodes.Status401Unauthorized, "mfa_required");
        problem["title"]!.GetValue<string>().Should().Be("Second factor required");
    }

    [Fact]
    public async Task Revoked_RefreshToken_Should_Not_Be_Accepted()
    {
        _factory.SenderMock.Reset();
        _factory.SenderMock
            .Setup(sender => sender.Send(It.IsAny<RefreshTokenCommand>(), It.IsAny<CancellationToken>()))
            .ThrowsAsync(new AuthApplicationException(
                "Invalid refresh token",
                "Session could not be refreshed.",
                StatusCodes.Status401Unauthorized,
                errorCode: "invalid_refresh_token"));

        var response = await _client.PostAsync(
            "/api/auth/refresh",
            JsonSerializationHelper.ToJsonContent(new RefreshTokenRequest(Guid.NewGuid(), Guid.NewGuid(), "revoked-token")));

        await response.ShouldBeProblemDetailsAsync(StatusCodes.Status401Unauthorized, "invalid_refresh_token");
    }
}
