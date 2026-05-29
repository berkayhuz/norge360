// <copyright file="AuthWebApplicationFactory.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using System.Security.Claims;
using System.Text.Encodings.Web;
using MediatR;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using Moq;
using Norge360.AspNetCore.TrustedGateway.Abstractions;
using Norge360.AspNetCore.TrustedGateway.Models;
using Norge360.Auth.API;
using Norge360.Auth.TestKit.Helpers;

namespace Norge360.Auth.TestKit.Fixtures;

public sealed class AuthWebApplicationFactory : WebApplicationFactory<Program>
{
    private readonly IReadOnlyDictionary<string, string?> _overrides;
    private readonly string _environment;

    public AuthWebApplicationFactory(
        IReadOnlyDictionary<string, string?>? overrides = null,
        string environment = "Testing")
    {
        _environment = environment;
        _overrides = overrides ?? TestConfiguration.CreateAuthApiDefaults();
    }

    public Mock<ISender> SenderMock { get; } = new(MockBehavior.Strict);

    public async Task InitializeAsync()
    {
        await Task.CompletedTask;
    }

    public HttpClient CreateAuthenticatedClient(Guid? userId = null, Guid? sessionId = null)
    {
        var client = CreateClient();
        client.DefaultRequestHeaders.Add(TestAuthenticationHandler.AuthHeaderName, "true");
        client.DefaultRequestHeaders.Add(TestAuthenticationHandler.UserHeaderName, (userId ?? Guid.NewGuid()).ToString());
        client.DefaultRequestHeaders.Add(TestAuthenticationHandler.SessionHeaderName, (sessionId ?? Guid.NewGuid()).ToString());
        return client;
    }

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.UseEnvironment(_environment);
        builder.ConfigureAppConfiguration(configuration =>
        {
            configuration.AddInMemoryCollection(_overrides);
        });

        builder.ConfigureServices(services =>
        {
            services.RemoveAll<ISender>();
            services.AddSingleton(SenderMock.Object);

            services.RemoveAll<ITrustedGatewayRequestValidator>();
            services.AddSingleton<ITrustedGatewayRequestValidator, AlwaysTrustedGatewayValidator>();

            services.AddAuthentication(options =>
                {
                    options.DefaultAuthenticateScheme = TestAuthenticationHandler.SchemeName;
                    options.DefaultChallengeScheme = TestAuthenticationHandler.SchemeName;
                })
                .AddScheme<AuthenticationSchemeOptions, TestAuthenticationHandler>(
                    TestAuthenticationHandler.SchemeName,
                    _ => { });
        });
    }

    protected override IHost CreateHost(IHostBuilder builder)
    {
        builder.ConfigureAppConfiguration((_, configuration) =>
        {
            configuration.AddInMemoryCollection(_overrides);
        });

        return base.CreateHost(builder);
    }

    public override async ValueTask DisposeAsync()
    {
        await Task.CompletedTask;
        await base.DisposeAsync();
    }

    private sealed class AlwaysTrustedGatewayValidator : ITrustedGatewayRequestValidator
    {
        public Task<TrustedGatewayValidationResult> ValidateAsync(HttpContext context, string correlationId, CancellationToken cancellationToken) =>
            Task.FromResult(TrustedGatewayValidationResult.Success());
    }

    private sealed class TestAuthenticationHandler(
        IOptionsMonitor<AuthenticationSchemeOptions> options,
        ILoggerFactory logger,
        UrlEncoder encoder)
        : AuthenticationHandler<AuthenticationSchemeOptions>(options, logger, encoder)
    {
        public const string SchemeName = "TestAuth";
        public const string AuthHeaderName = "X-Test-Auth";
        public const string UserHeaderName = "X-Test-User-Id";
        public const string SessionHeaderName = "X-Test-Session-Id";

        protected override Task<AuthenticateResult> HandleAuthenticateAsync()
        {
            if (!Request.Headers.TryGetValue(AuthHeaderName, out var value) ||
                !string.Equals(value.ToString(), "true", StringComparison.OrdinalIgnoreCase))
            {
                return Task.FromResult(AuthenticateResult.NoResult());
            }

            var userId = Request.Headers.TryGetValue(UserHeaderName, out var userHeader) && Guid.TryParse(userHeader, out var parsedUser)
                ? parsedUser
                : Guid.NewGuid();
            var sessionId = Request.Headers.TryGetValue(SessionHeaderName, out var sessionHeader) && Guid.TryParse(sessionHeader, out var parsedSession)
                ? parsedSession
                : Guid.NewGuid();

            var claims = new[]
            {
                new Claim(ClaimTypes.NameIdentifier, userId.ToString()),
                new Claim(ClaimTypes.Email, "tester@example.test"),
                new Claim(System.IdentityModel.Tokens.Jwt.JwtRegisteredClaimNames.Sub, userId.ToString()),
                new Claim(System.IdentityModel.Tokens.Jwt.JwtRegisteredClaimNames.Sid, sessionId.ToString()),
                new Claim(ClaimTypes.Role, "user"),
                new Claim("permission", "customers.read"),
                new Claim("permission", "customers.write"),
                new Claim("permission", "customer-intelligence.duplicates.read")
            };

            var identity = new ClaimsIdentity(claims, SchemeName);
            var principal = new ClaimsPrincipal(identity);
            var ticket = new AuthenticationTicket(principal, SchemeName);
            return Task.FromResult(AuthenticateResult.Success(ticket));
        }
    }
}
