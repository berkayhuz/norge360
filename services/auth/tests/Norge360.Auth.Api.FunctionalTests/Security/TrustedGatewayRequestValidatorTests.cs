// <copyright file="TrustedGatewayRequestValidatorTests.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using System.Net;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Logging.Abstractions;
using Norge360.AspNetCore.TrustedGateway.Abstractions;
using Norge360.AspNetCore.TrustedGateway.Models;
using Norge360.AspNetCore.TrustedGateway.Options;
using Norge360.AspNetCore.TrustedGateway.Validation;

namespace Norge360.Auth.Api.FunctionalTests.Security;

[Trait("Category", "SecurityRegression")]
public sealed class TrustedGatewayRequestValidatorTests
{
    [Fact]
    public async Task ValidateAsync_Should_Reject_Remote_Address_Outside_Allowed_Gateway_Surface()
    {
        var options = CreateOptions();
        var context = CreateContext(options, IPAddress.Parse("203.0.113.10"));
        var validator = CreateValidator(options);

        var result = await validator.ValidateAsync(context, "correlation-id", CancellationToken.None);

        Assert.False(result.Succeeded);
        Assert.Equal(TrustedGatewayFailureReason.InvalidRemoteAddress, result.FailureReason);
        Assert.Equal("trusted_gateway_invalid_remote_address", result.ErrorCode);
    }

    [Fact]
    public async Task ValidateAsync_Should_Not_Reject_Remote_Address_When_It_Is_Allowed()
    {
        var options = CreateOptions();
        var context = CreateContext(options, IPAddress.Parse("10.10.0.10"));
        var validator = CreateValidator(options);

        var result = await validator.ValidateAsync(context, "correlation-id", CancellationToken.None);

        Assert.False(result.Succeeded);
        Assert.NotEqual(TrustedGatewayFailureReason.InvalidRemoteAddress, result.FailureReason);
    }

    private static TrustedGatewayOptions CreateOptions() => new()
    {
        RequireTrustedGateway = true,
        AllowedSources = ["Norge360.ApiGateway"],
        AllowedGatewayProxies = ["10.10.0.10"],
        Keys =
        [
            new TrustedGatewayKeyOptions
            {
                KeyId = "gateway-test-key",
                Secret = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                Enabled = true,
                SignRequests = true
            }
        ]
    };

    private static TrustedGatewayRequestValidator CreateValidator(TrustedGatewayOptions options) =>
        new(options, new NoopReplayProtector(), NullLogger<TrustedGatewayRequestValidator>.Instance);

    private static DefaultHttpContext CreateContext(TrustedGatewayOptions options, IPAddress remoteAddress)
    {
        var context = new DefaultHttpContext();
        context.Connection.RemoteIpAddress = remoteAddress;
        context.Request.Method = HttpMethods.Post;
        context.Request.Path = "/api/auth/login";
        context.Request.Headers[options.KeyIdHeaderName] = "gateway-test-key";
        context.Request.Headers[options.SignatureHeaderName] = "00";
        context.Request.Headers[options.TimestampHeaderName] = DateTimeOffset.UtcNow.ToUnixTimeSeconds().ToString(System.Globalization.CultureInfo.InvariantCulture);
        context.Request.Headers[options.SourceHeaderName] = "Norge360.ApiGateway";
        context.Request.Headers[options.NonceHeaderName] = Guid.NewGuid().ToString("N");
        context.Request.Headers[options.ContentHashHeaderName] = "00";
        return context;
    }

    private sealed class NoopReplayProtector : ITrustedGatewayReplayProtector
    {
        public Task<bool> TryRegisterAsync(string keyId, string nonce, TimeSpan ttl, CancellationToken cancellationToken) =>
            Task.FromResult(true);
    }
}
