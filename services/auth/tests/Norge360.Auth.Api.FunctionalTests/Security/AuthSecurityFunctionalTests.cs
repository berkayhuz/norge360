// <copyright file="AuthSecurityFunctionalTests.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using FluentAssertions;
using MediatR;
using Moq;
using Norge360.Auth.Application.Features.Commands;
using Norge360.Auth.Contracts.Requests;
using Norge360.Auth.TestKit.Builders;
using Norge360.Auth.TestKit.Extensions;
using Norge360.Auth.TestKit.Fixtures;
using Norge360.Auth.TestKit.Helpers;

namespace Norge360.Auth.Api.FunctionalTests.Security;

public sealed class AuthSecurityFunctionalTests : IAsyncLifetime
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
    public async Task Cors_Preflight_Should_Allow_Configured_Origin()
    {
        using var request = new HttpRequestMessage(HttpMethod.Options, "/api/auth/login");
        request.Headers.Add("Origin", "https://localhost:7025");
        request.Headers.Add("Access-Control-Request-Method", "POST");

        var response = await _client.SendAsync(request);

        response.StatusCode.Should().Be(System.Net.HttpStatusCode.NoContent);
        response.Headers.TryGetValues("Access-Control-Allow-Origin", out var origins).Should().BeTrue();
        origins.Should().ContainSingle().Which.Should().Be("https://localhost:7025");
    }

    [Fact]
    public async Task Login_Should_Return_TooManyRequests_When_RateLimit_Is_Exceeded()
    {
        _factory.SenderMock.Reset();
        _factory.SenderMock
            .Setup(sender => sender.Send(It.IsAny<LoginCommand>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(AuthTestDataBuilder.TokenResponse());

        var request = AuthTestDataBuilder.LoginRequest().Build();
        var responses = new List<HttpResponseMessage>();
        for (var attempt = 0; attempt < 6; attempt++)
        {
            responses.Add(await _client.PostAsync("/api/auth/login", JsonSerializationHelper.ToJsonContent(request)));
        }

        responses.Take(5).Should().OnlyContain(response => response.StatusCode == System.Net.HttpStatusCode.OK);
        var throttledResponse = responses.Last();
        var problem = await throttledResponse.ShouldBeProblemDetailsAsync(StatusCodes.Status429TooManyRequests, "auth_rate_limit_exceeded");
        problem["title"]!.GetValue<string>().Should().Be("Rate limit exceeded");
    }

    [Fact]
    public async Task Unsafe_Cookie_Request_Should_Be_Rejected_Without_Allowed_Origin()
    {
        _factory.SenderMock.Reset();
        _factory.SenderMock
            .Setup(sender => sender.Send(It.IsAny<LogoutCommand>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(Unit.Value);

        using var request = new HttpRequestMessage(HttpMethod.Post, "/api/auth/logout")
        {
            Content = JsonSerializationHelper.ToJsonContent(new LogoutRequest(Guid.NewGuid(), Guid.NewGuid(), "token"))
        };
        request.Headers.Add("Cookie", "__Secure-Norge360-access=abc; __Secure-Norge360-refresh=def; __Secure-Norge360-session=ghi");

        var response = await _client.SendAsync(request);

        await response.ShouldBeProblemDetailsAsync(StatusCodes.Status403Forbidden, "cookie_origin_validation_failed");
    }

    [Fact]
    public async Task Logout_Without_Refresh_Context_Should_Clear_Cookies_And_Not_Revoke()
    {
        _factory.SenderMock.Reset();

        var response = await _client.PostAsync("/api/auth/logout", JsonSerializationHelper.ToJsonContent(new { }));

        response.StatusCode.Should().Be(System.Net.HttpStatusCode.NoContent);
        response.Headers.TryGetValues("Set-Cookie", out var cookies).Should().BeTrue();
        cookies.Should().Contain(cookie => cookie.Contains("__Secure-Norge360-access", StringComparison.Ordinal));
        cookies.Should().Contain(cookie => cookie.Contains("__Secure-Norge360-refresh", StringComparison.Ordinal));
        cookies.Should().Contain(cookie => cookie.Contains("__Secure-Norge360-session", StringComparison.Ordinal));
        cookies.Should().Contain(cookie =>
            cookie.Contains("__Secure-Norge360-access=", StringComparison.Ordinal) &&
            cookie.Contains("path=/", StringComparison.OrdinalIgnoreCase) &&
            cookie.Contains("expires=Thu, 01 Jan 1970 00:00:00 GMT", StringComparison.OrdinalIgnoreCase));
        cookies.Should().Contain(cookie =>
            cookie.Contains("__Secure-Norge360-refresh=", StringComparison.Ordinal) &&
            cookie.Contains("path=/api/auth", StringComparison.OrdinalIgnoreCase) &&
            cookie.Contains("expires=Thu, 01 Jan 1970 00:00:00 GMT", StringComparison.OrdinalIgnoreCase));
        cookies.Should().Contain(cookie =>
            cookie.Contains("__Secure-Norge360-session=", StringComparison.Ordinal) &&
            cookie.Contains("path=/api/auth", StringComparison.OrdinalIgnoreCase) &&
            cookie.Contains("expires=Thu, 01 Jan 1970 00:00:00 GMT", StringComparison.OrdinalIgnoreCase));
        _factory.SenderMock.Verify(
            sender => sender.Send(It.IsAny<LogoutCommand>(), It.IsAny<CancellationToken>()),
            Times.Never);
    }

    [Fact]
    public async Task Logout_With_Account_Web_Origin_Should_Revoke_Current_Session_And_Clear_Cookies()
    {
        var tenantId = Guid.NewGuid();
        var userId = Guid.NewGuid();
        var sessionId = Guid.NewGuid();
        _factory.SenderMock.Reset();
        _factory.SenderMock
            .Setup(sender => sender.Send(
                It.Is<LogoutCommand>(command =>
                    command.TenantId == tenantId &&
                    command.SessionId == sessionId &&
                    command.RefreshToken == "refresh-token"),
                It.IsAny<CancellationToken>()))
            .ReturnsAsync(Unit.Value);

        using var request = new HttpRequestMessage(HttpMethod.Post, "/api/auth/logout")
        {
            Content = JsonSerializationHelper.ToJsonContent(new { })
        };
        request.Headers.Add("Origin", "http://localhost:7004");
        request.Headers.Add("X-Test-Auth", "true");
        request.Headers.Add("X-Test-Tenant-Id", tenantId.ToString());
        request.Headers.Add("X-Test-User-Id", userId.ToString());
        request.Headers.Add("X-Test-Session-Id", sessionId.ToString());
        request.Headers.Add(
            "Cookie",
            $"__Secure-Norge360-access=access-token; __Secure-Norge360-refresh=refresh-token; __Secure-Norge360-session={sessionId:D}");

        var response = await _client.SendAsync(request);

        response.StatusCode.Should().Be(System.Net.HttpStatusCode.NoContent);
        response.Headers.TryGetValues("Set-Cookie", out var cookies).Should().BeTrue();
        cookies.Should().Contain(cookie => cookie.Contains("__Secure-Norge360-access=", StringComparison.Ordinal));
        cookies.Should().Contain(cookie => cookie.Contains("__Secure-Norge360-refresh=", StringComparison.Ordinal));
        cookies.Should().Contain(cookie => cookie.Contains("__Secure-Norge360-session=", StringComparison.Ordinal));
        _factory.SenderMock.VerifyAll();
    }

    [Fact]
    public async Task Security_Headers_Should_Be_Applied_On_Responses()
    {
        var response = await _client.GetAsync("/health/live");

        response.Headers.Contains("Content-Security-Policy").Should().BeTrue();
        response.Headers.Contains("Referrer-Policy").Should().BeTrue();
        response.Headers.Contains("Permissions-Policy").Should().BeTrue();
    }
}
