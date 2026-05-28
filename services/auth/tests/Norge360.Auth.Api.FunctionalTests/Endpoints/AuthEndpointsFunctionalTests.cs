// <copyright file="AuthEndpointsFunctionalTests.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using System.Net.Http.Json;
using FluentAssertions;
using FluentValidation;
using FluentValidation.Results;
using MediatR;
using Microsoft.AspNetCore.Mvc;
using Moq;
using Norge360.Auth.Application.Exceptions;
using Norge360.Auth.Application.Features.Commands;
using Norge360.Auth.Application.Records;
using Norge360.Auth.Contracts.Internal;
using Norge360.Auth.Contracts.Requests;
using Norge360.Auth.Contracts.Responses;
using Norge360.Auth.TestKit.Builders;
using Norge360.Auth.TestKit.Extensions;
using Norge360.Auth.TestKit.Fixtures;
using Norge360.Auth.TestKit.Helpers;

namespace Norge360.Auth.Api.FunctionalTests.Endpoints;

public sealed class AuthEndpointsFunctionalTests : IAsyncLifetime
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
    public async Task Register_Should_Return_Cookies_With_Secure_Flags()
    {
        _factory.SenderMock.Reset();
        var tokenResponse = AuthTestDataBuilder.TokenResponse();
        _factory.SenderMock
            .Setup(sender => sender.Send(It.IsAny<RegisterCommand>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(new AuthSessionResult.Issued(tokenResponse));

        var request = AuthTestDataBuilder.RegisterRequest().Build();

        var response = await _client.PostAsync("/api/auth/register", JsonSerializationHelper.ToJsonContent(request));

        response.StatusCode.Should().Be(System.Net.HttpStatusCode.OK);
        response.Headers.TryGetValues("Set-Cookie", out var cookies).Should().BeTrue();
        cookies.Should().NotBeNull();
        cookies!.Should().Contain(cookie => cookie.Contains("HttpOnly", StringComparison.OrdinalIgnoreCase));
        cookies.Should().Contain(cookie => cookie.Contains("Secure", StringComparison.OrdinalIgnoreCase));
        cookies.Should().Contain(cookie => cookie.Contains("SameSite=Lax", StringComparison.OrdinalIgnoreCase));
    }

    [Fact]
    public async Task Register_When_EmailConfirmation_Is_Required_Should_Return_Accepted_Without_Cookies()
    {
        _factory.SenderMock.Reset();
        _factory.SenderMock
            .Setup(sender => sender.Send(It.IsAny<RegisterCommand>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(new AuthSessionResult.PendingConfirmation(Guid.NewGuid(), Guid.NewGuid(), "jane.doe@example.com"));

        var response = await _client.PostAsync(
            "/api/auth/register",
            JsonSerializationHelper.ToJsonContent(AuthTestDataBuilder.RegisterRequest().Build()));

        response.StatusCode.Should().Be(System.Net.HttpStatusCode.Accepted);
        response.Headers.TryGetValues("Set-Cookie", out _).Should().BeFalse();
    }

    [Fact]
    public async Task AcceptInvitation_When_EmailConfirmation_Is_Required_Should_Return_Accepted_Without_Cookies()
    {
        _factory.SenderMock.Reset();
        _factory.SenderMock
            .Setup(sender => sender.Send(It.IsAny<AcceptTenantInvitationCommand>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(new AuthSessionResult.PendingConfirmation(Guid.NewGuid(), Guid.NewGuid(), "invitee@example.com"));

        var response = await _client.PostAsync(
            "/api/auth/invitations/accept",
            JsonSerializationHelper.ToJsonContent(new AcceptTenantInvitationRequest(
                Guid.NewGuid(),
                "invite-token",
                "invitee",
                "invitee@example.com",
                "Str0ng!Pass123",
                "Invitee",
                "Example")));

        response.StatusCode.Should().Be(System.Net.HttpStatusCode.Accepted);
        response.Headers.TryGetValues("Set-Cookie", out _).Should().BeFalse();
    }

    [Fact]
    public async Task AcceptInvitation_Should_Use_Request_TenantId_Not_Spoofed_Header_TenantId()
    {
        _factory.SenderMock.Reset();
        var requestTenantId = Guid.NewGuid();
        var spoofedHeaderTenantId = Guid.NewGuid();
        _factory.SenderMock
            .Setup(sender => sender.Send(It.IsAny<AcceptTenantInvitationCommand>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(new AuthSessionResult.PendingConfirmation(Guid.NewGuid(), Guid.NewGuid(), "invitee@example.com"));

        using var request = new HttpRequestMessage(HttpMethod.Post, "/api/auth/invitations/accept")
        {
            Content = JsonSerializationHelper.ToJsonContent(new AcceptTenantInvitationRequest(
                requestTenantId,
                "invite-token",
                "invitee",
                "invitee@example.com",
                "Str0ng!Pass123",
                "Invitee",
                "Example"))
        };
        request.Headers.Add("X-Tenant-Id", spoofedHeaderTenantId.ToString("D"));

        var response = await _client.SendAsync(request);

        response.StatusCode.Should().Be(System.Net.HttpStatusCode.Accepted);
        _factory.SenderMock.Verify(
            sender => sender.Send(
                It.Is<AcceptTenantInvitationCommand>(cmd => cmd.TenantId == requestTenantId),
                It.IsAny<CancellationToken>()),
            Times.Once);
    }

    [Fact]
    public async Task Register_Should_Return_ProblemDetails_For_Registration_Conflict()
    {
        _factory.SenderMock.Reset();
        _factory.SenderMock
            .Setup(sender => sender.Send(It.IsAny<RegisterCommand>(), It.IsAny<CancellationToken>()))
            .ThrowsAsync(new AuthApplicationException(
                "Registration could not be completed",
                "The registration request could not be completed with the supplied identity.",
                StatusCodes.Status409Conflict,
                errorCode: "registration_conflict"));

        var response = await _client.PostAsync(
            "/api/auth/register",
            JsonSerializationHelper.ToJsonContent(AuthTestDataBuilder.RegisterRequest().Build()));

        var problem = await response.ShouldBeProblemDetailsAsync(StatusCodes.Status409Conflict, "registration_conflict");
        problem["title"]!.GetValue<string>().Should().Be("Registration could not be completed");
    }

    [Fact]
    public async Task Register_Should_Return_ProblemDetails_For_Duplicate_Email_Without_Enumeration_Details()
    {
        _factory.SenderMock.Reset();
        _factory.SenderMock
            .Setup(sender => sender.Send(It.IsAny<RegisterCommand>(), It.IsAny<CancellationToken>()))
            .ThrowsAsync(new AuthApplicationException(
                "Registration could not be completed",
                "An account with this email address already exists.",
                StatusCodes.Status409Conflict,
                errorCode: "duplicate_email"));

        var response = await _client.PostAsync(
            "/api/auth/register",
            JsonSerializationHelper.ToJsonContent(AuthTestDataBuilder.RegisterRequest().Build()));

        var problem = await response.ShouldBeProblemDetailsAsync(StatusCodes.Status409Conflict, "duplicate_email");
        problem["title"]!.GetValue<string>().Should().Be("Registration could not be completed");
    }

    [Fact]
    public async Task ConfirmEmail_Should_Return_NoContent_On_Success()
    {
        _factory.SenderMock.Reset();
        _factory.SenderMock
            .Setup(sender => sender.Send(It.IsAny<ConfirmEmailCommand>(), It.IsAny<CancellationToken>()))
            .Returns(Task.CompletedTask);

        var response = await _client.PostAsync(
            "/api/auth/confirm-email",
            JsonSerializationHelper.ToJsonContent(new ConfirmEmailRequest(Guid.NewGuid(), Guid.NewGuid(), "confirm-token")));

        response.StatusCode.Should().Be(System.Net.HttpStatusCode.NoContent);
    }

    [Fact]
    public async Task ConfirmEmail_Should_Use_Request_TenantId_Not_Spoofed_Header_TenantId()
    {
        _factory.SenderMock.Reset();
        var requestTenantId = Guid.NewGuid();
        var spoofedHeaderTenantId = Guid.NewGuid();
        _factory.SenderMock
            .Setup(sender => sender.Send(It.IsAny<ConfirmEmailCommand>(), It.IsAny<CancellationToken>()))
            .Returns(Task.CompletedTask);

        using var request = new HttpRequestMessage(HttpMethod.Post, "/api/auth/confirm-email")
        {
            Content = JsonSerializationHelper.ToJsonContent(new ConfirmEmailRequest(requestTenantId, Guid.NewGuid(), "confirm-token"))
        };
        request.Headers.Add("X-Tenant-Id", spoofedHeaderTenantId.ToString("D"));

        var response = await _client.SendAsync(request);

        response.StatusCode.Should().Be(System.Net.HttpStatusCode.NoContent);
        _factory.SenderMock.Verify(
            sender => sender.Send(
                It.Is<ConfirmEmailCommand>(cmd => cmd.TenantId == requestTenantId),
                It.IsAny<CancellationToken>()),
            Times.Once);
    }

    [Fact]
    public async Task ConfirmEmail_Should_Return_ProblemDetails_For_Invalid_Token()
    {
        _factory.SenderMock.Reset();
        _factory.SenderMock
            .Setup(sender => sender.Send(It.IsAny<ConfirmEmailCommand>(), It.IsAny<CancellationToken>()))
            .ThrowsAsync(new AuthApplicationException(
                "Invalid token",
                "The supplied email confirmation token is invalid or expired.",
                StatusCodes.Status400BadRequest,
                errorCode: "invalid_email_confirmation_token"));

        var response = await _client.PostAsync(
            "/api/auth/confirm-email",
            JsonSerializationHelper.ToJsonContent(new ConfirmEmailRequest(Guid.NewGuid(), Guid.NewGuid(), "invalid-token")));

        var problem = await response.ShouldBeProblemDetailsAsync(StatusCodes.Status400BadRequest, "invalid_email_confirmation_token");
        problem["title"]!.GetValue<string>().Should().Be("Invalid token");
    }

    [Fact]
    public async Task ConfirmEmail_Should_Return_ProblemDetails_On_Validation_Error()
    {
        _factory.SenderMock.Reset();
        var validationFailures = new[] { new ValidationFailure("Token", "Token is required.") };
        _factory.SenderMock
            .Setup(sender => sender.Send(It.IsAny<ConfirmEmailCommand>(), It.IsAny<CancellationToken>()))
            .ThrowsAsync(new ValidationException(validationFailures));

        var response = await _client.PostAsync(
            "/api/auth/confirm-email",
            JsonSerializationHelper.ToJsonContent(new ConfirmEmailRequest(Guid.NewGuid(), Guid.NewGuid(), string.Empty)));

        var problem = await response.ShouldBeProblemDetailsAsync(StatusCodes.Status400BadRequest);
        problem["title"]!.GetValue<string>().Should().Be("Validation failed");
        problem["errors"]!["Token"]![0]!.GetValue<string>().Should().Be("Token is required.");
    }

    [Fact]
    public async Task ForgotPassword_Should_Return_Accepted_On_Success()
    {
        _factory.SenderMock.Reset();
        _factory.SenderMock
            .Setup(sender => sender.Send(It.IsAny<ForgotPasswordCommand>(), It.IsAny<CancellationToken>()))
            .Returns(Task.CompletedTask);

        var response = await _client.PostAsync(
            "/api/auth/forgot-password",
            JsonSerializationHelper.ToJsonContent(new ForgotPasswordRequest(Guid.NewGuid(), "jane@example.com")));

        response.StatusCode.Should().Be(System.Net.HttpStatusCode.Accepted);
    }

    [Fact]
    public async Task ForgotPassword_Should_Return_ProblemDetails_On_Validation_Error()
    {
        _factory.SenderMock.Reset();
        var validationFailures = new[] { new ValidationFailure("Email", "Email is required.") };
        _factory.SenderMock
            .Setup(sender => sender.Send(It.IsAny<ForgotPasswordCommand>(), It.IsAny<CancellationToken>()))
            .ThrowsAsync(new ValidationException(validationFailures));

        var response = await _client.PostAsync(
            "/api/auth/forgot-password",
            JsonSerializationHelper.ToJsonContent(new ForgotPasswordRequest(Guid.NewGuid(), string.Empty)));

        var problem = await response.ShouldBeProblemDetailsAsync(StatusCodes.Status400BadRequest);
        problem["title"]!.GetValue<string>().Should().Be("Validation failed");
        problem["errors"]!["Email"]![0]!.GetValue<string>().Should().Be("Email is required.");
    }

    [Fact]
    public async Task ForgotPassword_Should_Use_Dedicated_RateLimit_Window()
    {
        var overrides = TestConfiguration.CreateAuthApiDefaults();
        overrides["Security:RateLimiting:Global:PermitLimit"] = "100";
        overrides["Security:RateLimiting:PasswordRecovery:PermitLimit"] = "1";
        overrides["Security:RateLimiting:PasswordRecovery:WindowSeconds"] = "60";

        await using var factory = new AuthWebApplicationFactory(overrides);
        using var client = factory.CreateClient();
        factory.SenderMock
            .Setup(sender => sender.Send(It.IsAny<ForgotPasswordCommand>(), It.IsAny<CancellationToken>()))
            .Returns(Task.CompletedTask);

        var request = new ForgotPasswordRequest(Guid.NewGuid(), "jane@example.com");

        var first = await client.PostAsync("/api/auth/forgot-password", JsonSerializationHelper.ToJsonContent(request));
        var second = await client.PostAsync("/api/auth/forgot-password", JsonSerializationHelper.ToJsonContent(request));

        first.StatusCode.Should().Be(System.Net.HttpStatusCode.Accepted);
        await second.ShouldBeProblemDetailsAsync(StatusCodes.Status429TooManyRequests, "auth_rate_limit_exceeded");
    }

    [Fact]
    public async Task ResetPassword_Should_Return_NoContent_On_Success()
    {
        _factory.SenderMock.Reset();
        _factory.SenderMock
            .Setup(sender => sender.Send(It.IsAny<ResetPasswordCommand>(), It.IsAny<CancellationToken>()))
            .Returns(Task.CompletedTask);

        var response = await _client.PostAsync(
            "/api/auth/reset-password",
            JsonSerializationHelper.ToJsonContent(
                new ResetPasswordRequest(Guid.NewGuid(), Guid.NewGuid(), "reset-token", "Str0ng!Pass123")));

        response.StatusCode.Should().Be(System.Net.HttpStatusCode.NoContent);
    }

    [Fact]
    public async Task ResetPassword_Should_Use_Request_TenantId_Not_Spoofed_Header_TenantId()
    {
        _factory.SenderMock.Reset();
        var requestTenantId = Guid.NewGuid();
        var spoofedHeaderTenantId = Guid.NewGuid();
        _factory.SenderMock
            .Setup(sender => sender.Send(It.IsAny<ResetPasswordCommand>(), It.IsAny<CancellationToken>()))
            .Returns(Task.CompletedTask);

        using var request = new HttpRequestMessage(HttpMethod.Post, "/api/auth/reset-password")
        {
            Content = JsonSerializationHelper.ToJsonContent(
                new ResetPasswordRequest(requestTenantId, Guid.NewGuid(), "reset-token", "Str0ng!Pass123"))
        };
        request.Headers.Add("X-Tenant-Id", spoofedHeaderTenantId.ToString("D"));

        var response = await _client.SendAsync(request);

        response.StatusCode.Should().Be(System.Net.HttpStatusCode.NoContent);
        _factory.SenderMock.Verify(
            sender => sender.Send(
                It.Is<ResetPasswordCommand>(cmd => cmd.TenantId == requestTenantId),
                It.IsAny<CancellationToken>()),
            Times.Once);
    }

    [Fact]
    public async Task ResetPassword_Should_Return_ProblemDetails_For_Invalid_Token()
    {
        _factory.SenderMock.Reset();
        _factory.SenderMock
            .Setup(sender => sender.Send(It.IsAny<ResetPasswordCommand>(), It.IsAny<CancellationToken>()))
            .ThrowsAsync(new AuthApplicationException(
                "Invalid token",
                "The supplied password reset token is invalid or expired.",
                StatusCodes.Status400BadRequest,
                errorCode: "invalid_password_reset_token"));

        var response = await _client.PostAsync(
            "/api/auth/reset-password",
            JsonSerializationHelper.ToJsonContent(
                new ResetPasswordRequest(Guid.NewGuid(), Guid.NewGuid(), "invalid-token", "Str0ng!Pass123")));

        var problem = await response.ShouldBeProblemDetailsAsync(StatusCodes.Status400BadRequest, "invalid_password_reset_token");
        problem["title"]!.GetValue<string>().Should().Be("Invalid token");
    }

    [Fact]
    public async Task ResetPassword_Should_Return_ProblemDetails_On_Validation_Error()
    {
        _factory.SenderMock.Reset();
        var validationFailures = new[] { new ValidationFailure("NewPassword", "Password is required.") };
        _factory.SenderMock
            .Setup(sender => sender.Send(It.IsAny<ResetPasswordCommand>(), It.IsAny<CancellationToken>()))
            .ThrowsAsync(new ValidationException(validationFailures));

        var response = await _client.PostAsync(
            "/api/auth/reset-password",
            JsonSerializationHelper.ToJsonContent(
                new ResetPasswordRequest(Guid.NewGuid(), Guid.NewGuid(), "token", string.Empty)));

        var problem = await response.ShouldBeProblemDetailsAsync(StatusCodes.Status400BadRequest);
        problem["title"]!.GetValue<string>().Should().Be("Validation failed");
        problem["errors"]!["NewPassword"]![0]!.GetValue<string>().Should().Be("Password is required.");
    }

    [Fact]
    public async Task Login_Should_Return_Cookies_With_Secure_Flags()
    {
        _factory.SenderMock.Reset();
        var tokenResponse = AuthTestDataBuilder.TokenResponse();
        _factory.SenderMock
            .Setup(sender => sender.Send(It.IsAny<LoginCommand>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(tokenResponse);

        var request = AuthTestDataBuilder.LoginRequest().Build();

        var response = await _client.PostAsync("/api/auth/login", JsonSerializationHelper.ToJsonContent(request));

        response.StatusCode.Should().Be(System.Net.HttpStatusCode.OK);
        response.Headers.TryGetValues("Set-Cookie", out var cookies).Should().BeTrue();
        cookies.Should().NotBeNull();
        cookies!.Should().Contain(cookie => cookie.Contains("HttpOnly", StringComparison.OrdinalIgnoreCase));
        cookies.Should().Contain(cookie => cookie.Contains("Secure", StringComparison.OrdinalIgnoreCase));
        cookies.Should().Contain(cookie => cookie.Contains("SameSite=Lax", StringComparison.OrdinalIgnoreCase));
    }

    [Fact]
    public async Task Login_Should_Return_ProblemDetails_On_Validation_Error()
    {
        _factory.SenderMock.Reset();
        var validationFailures = new[] { new ValidationFailure("Password", "Password is required.") };
        _factory.SenderMock
            .Setup(sender => sender.Send(It.IsAny<LoginCommand>(), It.IsAny<CancellationToken>()))
            .ThrowsAsync(new ValidationException(validationFailures));

        var response = await _client.PostAsync(
            "/api/auth/login",
            JsonSerializationHelper.ToJsonContent(new LoginRequest(Guid.NewGuid(), "jane@example.com", string.Empty)));

        var problem = await response.ShouldBeProblemDetailsAsync(StatusCodes.Status400BadRequest);
        problem["title"]!.GetValue<string>().Should().Be("Validation failed");
        problem["errors"]!["Password"]![0]!.GetValue<string>().Should().Be("Password is required.");
    }

    [Fact]
    public async Task Login_Should_Return_ProblemDetails_For_Mfa_Required()
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
    public async Task Login_Should_Return_RateLimitProblem_When_Window_Is_Exceeded()
    {
        var overrides = TestConfiguration.CreateAuthApiDefaults();
        overrides["Security:RateLimiting:Global:PermitLimit"] = "100";
        overrides["Security:RateLimiting:Login:PermitLimit"] = "1";
        overrides["Security:RateLimiting:Login:WindowSeconds"] = "60";

        await using var factory = new AuthWebApplicationFactory(overrides);
        using var client = factory.CreateClient();
        factory.SenderMock
            .Setup(sender => sender.Send(It.IsAny<LoginCommand>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(AuthTestDataBuilder.TokenResponse());

        var request = AuthTestDataBuilder.LoginRequest().Build();

        var first = await client.PostAsync("/api/auth/login", JsonSerializationHelper.ToJsonContent(request));
        var second = await client.PostAsync("/api/auth/login", JsonSerializationHelper.ToJsonContent(request));

        first.StatusCode.Should().Be(System.Net.HttpStatusCode.OK);
        await second.ShouldBeProblemDetailsAsync(StatusCodes.Status429TooManyRequests, "auth_rate_limit_exceeded");
    }

    [Fact]
    public async Task Login_Should_Not_Allow_RateLimit_Bypass_With_Spoofed_Tenant_Header()
    {
        var overrides = TestConfiguration.CreateAuthApiDefaults();
        overrides["Security:RateLimiting:Global:PermitLimit"] = "100";
        overrides["Security:RateLimiting:Login:PermitLimit"] = "1";
        overrides["Security:RateLimiting:Login:WindowSeconds"] = "60";

        await using var factory = new AuthWebApplicationFactory(overrides);
        using var client = factory.CreateClient();
        factory.SenderMock
            .Setup(sender => sender.Send(It.IsAny<LoginCommand>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(AuthTestDataBuilder.TokenResponse());

        var requestBody = new LoginRequest(Guid.Empty, "jane@example.com", "Password123!");

        using var firstRequest = new HttpRequestMessage(HttpMethod.Post, "/api/auth/login")
        {
            Content = JsonSerializationHelper.ToJsonContent(requestBody)
        };
        firstRequest.Headers.Add("X-Tenant-Id", Guid.NewGuid().ToString("D"));

        using var secondRequest = new HttpRequestMessage(HttpMethod.Post, "/api/auth/login")
        {
            Content = JsonSerializationHelper.ToJsonContent(requestBody)
        };
        secondRequest.Headers.Add("X-Tenant-Id", Guid.NewGuid().ToString("D"));

        var first = await client.SendAsync(firstRequest);
        var second = await client.SendAsync(secondRequest);

        first.StatusCode.Should().Be(System.Net.HttpStatusCode.OK);
        await second.ShouldBeProblemDetailsAsync(StatusCodes.Status429TooManyRequests, "auth_rate_limit_exceeded");
    }

    [Fact]
    public async Task Refresh_Should_Return_ProblemDetails_With_ErrorCode_For_Invalid_RefreshToken()
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
            JsonSerializationHelper.ToJsonContent(new RefreshTokenRequest(Guid.NewGuid(), Guid.NewGuid(), "invalid-token")));

        var problem = await response.ShouldBeProblemDetailsAsync(StatusCodes.Status401Unauthorized, "invalid_refresh_token");
        problem["title"]!.GetValue<string>().Should().Be("Invalid refresh token");
    }

    [Fact]
    public async Task Refresh_Should_Be_Blocked_When_Tenant_Is_Not_Resolved_And_Request_Tenant_Is_Empty()
    {
        var response = await _client.PostAsync(
            "/api/auth/refresh",
            JsonSerializationHelper.ToJsonContent(new RefreshTokenRequest(Guid.Empty, Guid.NewGuid(), "refresh-token")));

        response.StatusCode.Should().Be(System.Net.HttpStatusCode.BadRequest);
    }

    [Fact]
    public async Task Refresh_Should_Use_Cookie_Refresh_Context_When_TokenTransport_Is_CookiesOnly()
    {
        _factory.SenderMock.Reset();
        var tenantId = Guid.NewGuid();
        var cookieSessionId = Guid.NewGuid();
        const string cookieRefreshToken = "cookie-refresh-token";
        var bodySessionId = Guid.NewGuid();
        const string bodyRefreshToken = "body-refresh-token";
        RefreshTokenCommand? capturedCommand = null;

        _factory.SenderMock
            .Setup(sender => sender.Send(
                It.Is<IRequest<AuthenticationTokenResponse>>(command => command is RefreshTokenCommand),
                It.IsAny<CancellationToken>()))
            .Callback<IRequest<AuthenticationTokenResponse>, CancellationToken>((command, _) => capturedCommand = (RefreshTokenCommand)command)
            .ReturnsAsync(AuthTestDataBuilder.TokenResponse(tenantId: tenantId));

        using var request = new HttpRequestMessage(HttpMethod.Post, "/api/auth/refresh")
        {
            Content = JsonSerializationHelper.ToJsonContent(new RefreshTokenRequest(tenantId, bodySessionId, bodyRefreshToken))
        };
        request.Headers.Add("Origin", "https://localhost:7025");
        request.Headers.Add("Cookie", $"__Secure-Norge360-refresh={cookieRefreshToken}; __Secure-Norge360-session={cookieSessionId:D}");

        var response = await _client.SendAsync(request);

        response.StatusCode.Should().Be(System.Net.HttpStatusCode.OK);
        capturedCommand.Should().NotBeNull();
        capturedCommand!.SessionId.Should().Be(cookieSessionId);
        capturedCommand.RefreshToken.Should().Be(cookieRefreshToken);
    }

    [Fact]
    public async Task SessionStatus_Should_Require_Authentication()
    {
        var response = await _client.GetAsync("/api/auth/session-status");

        response.StatusCode.Should().Be(System.Net.HttpStatusCode.Unauthorized);
    }

    [Fact]
    public async Task SessionStatus_Should_Return_Context_For_Authenticated_User()
    {
        var tenantId = Guid.NewGuid();
        var userId = Guid.NewGuid();
        var sessionId = Guid.NewGuid();
        using var authenticatedClient = _factory.CreateAuthenticatedClient(tenantId, userId, sessionId);

        var response = await authenticatedClient.GetAsync("/api/auth/session-status");

        response.StatusCode.Should().Be(System.Net.HttpStatusCode.OK);
        var payload = await response.Content.ReadFromJsonAsync<AuthSessionStatusResponse>();
        payload.Should().NotBeNull();
        payload!.TenantId.Should().Be(tenantId);
        payload.UserId.Should().Be(userId);
        payload.SessionId.Should().Be(sessionId);
        payload!.Email.Should().Be("tester@example.test");
        payload.Roles.Should().Contain("tenant-user");
        payload.Permissions.Should().Contain(["customers.read", "customers.write"]);
        payload.AccountStatus.Should().Be("active");
        payload.EmailConfirmed.Should().BeTrue();
    }

    [Fact]
    public async Task ResendConfirmEmail_Should_Return_Accepted_On_Success()
    {
        _factory.SenderMock.Reset();
        _factory.SenderMock
            .Setup(sender => sender.Send(It.IsAny<ResendEmailConfirmationCommand>(), It.IsAny<CancellationToken>()))
            .Returns(Task.CompletedTask);

        var response = await _client.PostAsync(
            "/api/auth/resend-confirm-email",
            JsonSerializationHelper.ToJsonContent(new ResendEmailConfirmationRequest(Guid.NewGuid(), "user@example.com")));

        response.StatusCode.Should().Be(System.Net.HttpStatusCode.Accepted);
    }

    [Fact]
    public async Task ResendConfirmEmail_Should_Use_Request_TenantId_Not_Spoofed_Header_TenantId()
    {
        _factory.SenderMock.Reset();
        var requestTenantId = Guid.NewGuid();
        var spoofedHeaderTenantId = Guid.NewGuid();
        _factory.SenderMock
            .Setup(sender => sender.Send(It.IsAny<ResendEmailConfirmationCommand>(), It.IsAny<CancellationToken>()))
            .Returns(Task.CompletedTask);

        using var request = new HttpRequestMessage(HttpMethod.Post, "/api/auth/resend-confirm-email")
        {
            Content = JsonSerializationHelper.ToJsonContent(new ResendEmailConfirmationRequest(requestTenantId, "user@example.com"))
        };
        request.Headers.Add("X-Tenant-Id", spoofedHeaderTenantId.ToString("D"));

        var response = await _client.SendAsync(request);

        response.StatusCode.Should().Be(System.Net.HttpStatusCode.Accepted);
        _factory.SenderMock.Verify(
            sender => sender.Send(
                It.Is<ResendEmailConfirmationCommand>(cmd => cmd.TenantId == requestTenantId),
                It.IsAny<CancellationToken>()),
            Times.Once);
    }

    [Fact]
    public async Task ConfirmEmailChange_Should_Return_NoContent_And_Clear_Cookies()
    {
        _factory.SenderMock.Reset();
        _factory.SenderMock
            .Setup(sender => sender.Send(It.IsAny<ConfirmEmailChangeCommand>(), It.IsAny<CancellationToken>()))
            .Returns(Task.CompletedTask);

        var response = await _client.PostAsync(
            "/api/auth/confirm-email-change",
            JsonSerializationHelper.ToJsonContent(new ConfirmEmailChangeRequest(Guid.NewGuid(), Guid.NewGuid(), "new@example.com", "token")));

        response.StatusCode.Should().Be(System.Net.HttpStatusCode.NoContent);
        response.Headers.TryGetValues("Set-Cookie", out var cookies).Should().BeTrue();
        cookies.Should().Contain(cookie => cookie.Contains("__Secure-Norge360-access=", StringComparison.Ordinal));
        cookies.Should().Contain(cookie => cookie.Contains("__Secure-Norge360-refresh=", StringComparison.Ordinal));
        cookies.Should().Contain(cookie => cookie.Contains("__Secure-Norge360-session=", StringComparison.Ordinal));
    }

    [Fact]
    public async Task ConfirmEmailChange_Should_Use_Request_TenantId_Not_Spoofed_Header_TenantId()
    {
        _factory.SenderMock.Reset();
        var requestTenantId = Guid.NewGuid();
        var spoofedHeaderTenantId = Guid.NewGuid();
        _factory.SenderMock
            .Setup(sender => sender.Send(It.IsAny<ConfirmEmailChangeCommand>(), It.IsAny<CancellationToken>()))
            .Returns(Task.CompletedTask);

        using var request = new HttpRequestMessage(HttpMethod.Post, "/api/auth/confirm-email-change")
        {
            Content = JsonSerializationHelper.ToJsonContent(
                new ConfirmEmailChangeRequest(requestTenantId, Guid.NewGuid(), "new@example.com", "token"))
        };
        request.Headers.Add("X-Tenant-Id", spoofedHeaderTenantId.ToString("D"));

        var response = await _client.SendAsync(request);

        response.StatusCode.Should().Be(System.Net.HttpStatusCode.NoContent);
        _factory.SenderMock.Verify(
            sender => sender.Send(
                It.Is<ConfirmEmailChangeCommand>(cmd => cmd.TenantId == requestTenantId),
                It.IsAny<CancellationToken>()),
            Times.Once);
    }

    [Fact]
    public async Task Logout_Should_Swallow_InvalidRefreshToken_And_Return_NoContent()
    {
        _factory.SenderMock.Reset();
        _factory.SenderMock
            .Setup(sender => sender.Send(It.IsAny<LogoutCommand>(), It.IsAny<CancellationToken>()))
            .ThrowsAsync(new AuthApplicationException(
                "Invalid refresh token",
                "Session could not be revoked.",
                StatusCodes.Status401Unauthorized,
                errorCode: "invalid_refresh_token"));

        using var request = new HttpRequestMessage(HttpMethod.Post, "/api/auth/logout")
        {
            Content = JsonSerializationHelper.ToJsonContent(new LogoutRequest(Guid.NewGuid(), Guid.NewGuid(), "refresh-token"))
        };
        request.Headers.Add("Origin", "https://localhost:7025");
        request.Headers.Add("Cookie", "__Secure-Norge360-refresh=refresh-token; __Secure-Norge360-session=00000000-0000-0000-0000-000000000123");

        var response = await _client.SendAsync(request);

        response.StatusCode.Should().Be(System.Net.HttpStatusCode.NoContent);
    }

    [Fact]
    public async Task Logout_Should_Use_Principal_Tenant_When_Request_Tenant_Is_Empty_And_Refresh_Context_Provided()
    {
        var principalTenantId = Guid.NewGuid();
        var principalUserId = Guid.NewGuid();
        var principalSessionId = Guid.NewGuid();
        var requestedSessionId = Guid.NewGuid();
        const string refreshToken = "refresh-from-cookie";
        LogoutCommand? capturedCommand = null;

        using var client = _factory.CreateAuthenticatedClient(principalTenantId, principalUserId, principalSessionId);
        _factory.SenderMock.Reset();
        _factory.SenderMock
            .Setup(sender => sender.Send(It.IsAny<LogoutCommand>(), It.IsAny<CancellationToken>()))
            .Callback<IRequest<Unit>, CancellationToken>((command, _) => capturedCommand = (LogoutCommand)command)
            .ReturnsAsync(Unit.Value);

        using var request = new HttpRequestMessage(HttpMethod.Post, "/api/auth/logout")
        {
            Content = JsonSerializationHelper.ToJsonContent(new LogoutRequest(Guid.Empty, requestedSessionId, null))
        };
        request.Headers.Add("Origin", "https://localhost:7025");
        request.Headers.Add("Cookie", $"__Secure-Norge360-refresh={refreshToken}; __Secure-Norge360-session={requestedSessionId:D}");
        request.Headers.Add("X-Tenant-Id", Guid.NewGuid().ToString("D"));

        var response = await client.SendAsync(request);

        response.StatusCode.Should().Be(System.Net.HttpStatusCode.NoContent);
        capturedCommand.Should().NotBeNull();
        capturedCommand!.TenantId.Should().Be(principalTenantId);
        capturedCommand.SessionId.Should().Be(requestedSessionId);
        capturedCommand.RefreshToken.Should().Be(refreshToken);
    }

    [Fact]
    public async Task CreateWorkspace_Should_Return_Ok_And_Set_Cookies_For_Authenticated_User()
    {
        var tenantId = Guid.NewGuid();
        var userId = Guid.NewGuid();
        var sessionId = Guid.NewGuid();
        using var client = _factory.CreateAuthenticatedClient(tenantId, userId, sessionId);

        _factory.SenderMock.Reset();
        _factory.SenderMock
            .Setup(sender => sender.Send(It.IsAny<CreateWorkspaceCommand>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(AuthTestDataBuilder.TokenResponse(tenantId: tenantId, userId: userId, sessionId: sessionId));

        var response = await client.PostAsync(
            "/api/auth/workspaces",
            JsonSerializationHelper.ToJsonContent(new CreateWorkspaceRequest("Acme Workspace", "en-US")));

        response.StatusCode.Should().Be(System.Net.HttpStatusCode.OK);
        response.Headers.TryGetValues("Set-Cookie", out var cookies).Should().BeTrue();
        cookies.Should().Contain(cookie => cookie.Contains("__Secure-Norge360-access=", StringComparison.Ordinal));
    }

    [Fact]
    public async Task SwitchWorkspace_Should_Return_Ok_And_Set_Cookies_For_Authenticated_User()
    {
        var currentTenantId = Guid.NewGuid();
        var targetTenantId = Guid.NewGuid();
        var userId = Guid.NewGuid();
        var sessionId = Guid.NewGuid();
        using var client = _factory.CreateAuthenticatedClient(currentTenantId, userId, sessionId);

        _factory.SenderMock.Reset();
        _factory.SenderMock
            .Setup(sender => sender.Send(It.IsAny<SwitchWorkspaceCommand>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(AuthTestDataBuilder.TokenResponse(tenantId: targetTenantId, userId: userId, sessionId: sessionId));

        var response = await client.PostAsync(
            "/api/auth/workspaces/switch",
            JsonSerializationHelper.ToJsonContent(new SwitchWorkspaceRequest(targetTenantId)));

        response.StatusCode.Should().Be(System.Net.HttpStatusCode.OK);
        response.Headers.TryGetValues("Set-Cookie", out var cookies).Should().BeTrue();
        cookies.Should().Contain(cookie => cookie.Contains("__Secure-Norge360-refresh=", StringComparison.Ordinal));
    }

    [Fact]
    public async Task DeleteWorkspace_Should_Return_NoContent_For_Authenticated_User()
    {
        var currentTenantId = Guid.NewGuid();
        var targetTenantId = Guid.NewGuid();
        var userId = Guid.NewGuid();
        var sessionId = Guid.NewGuid();
        using var client = _factory.CreateAuthenticatedClient(currentTenantId, userId, sessionId);

        _factory.SenderMock.Reset();
        _factory.SenderMock
            .Setup(sender => sender.Send(It.IsAny<DeleteWorkspaceCommand>(), It.IsAny<CancellationToken>()))
            .Returns(Task.CompletedTask);

        var response = await client.DeleteAsync($"/api/auth/workspaces/{targetTenantId:D}");

        response.StatusCode.Should().Be(System.Net.HttpStatusCode.NoContent);
    }

    [Fact]
    public async Task ListWorkspaces_Should_Return_Mapped_Response()
    {
        var tenantId = Guid.NewGuid();
        var userId = Guid.NewGuid();
        var sessionId = Guid.NewGuid();
        var workspaceTenantId = Guid.NewGuid();
        using var client = _factory.CreateAuthenticatedClient(tenantId, userId, sessionId);

        _factory.SenderMock.Reset();
        _factory.SenderMock
            .Setup(sender => sender.Send(It.IsAny<ListUserWorkspaceMembershipsCommand>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(
            [
                new InternalOrganizationMembershipSummaryResponse(
                    Guid.NewGuid(),
                    workspaceTenantId,
                    "Acme",
                    "acme",
                    "active",
                    true,
                    DateTimeOffset.UtcNow,
                    DateTimeOffset.UtcNow,
                    ["owner"])
            ]);

        var response = await client.GetAsync("/api/auth/workspaces");

        response.StatusCode.Should().Be(System.Net.HttpStatusCode.OK);
        var payload = await response.Content.ReadFromJsonAsync<IReadOnlyCollection<WorkspaceSummaryResponse>>();
        payload.Should().NotBeNull();
        var workspace = payload!.Should().ContainSingle().Subject;
        workspace.TenantId.Should().Be(workspaceTenantId);
        workspace.Role.Should().Be("owner");
    }
}
