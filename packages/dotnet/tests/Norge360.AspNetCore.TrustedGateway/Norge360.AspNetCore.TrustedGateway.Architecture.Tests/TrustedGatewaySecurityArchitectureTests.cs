// <copyright file="TrustedGatewaySecurityArchitectureTests.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Logging.Abstractions;
using Norge360.AspNetCore.TrustedGateway.Abstractions;
using Norge360.AspNetCore.TrustedGateway.Models;
using Norge360.AspNetCore.TrustedGateway.Options;
using Norge360.AspNetCore.TrustedGateway.Signing;
using Norge360.AspNetCore.TrustedGateway.Validation;

namespace Norge360.AspNetCore.TrustedGateway.Architecture.Tests;

public class TrustedGatewaySecurityArchitectureTests
{
    [Fact]
    public async Task ValidateAsync_should_fail_when_required_headers_are_missing()
    {
        var validator = CreateValidator(new AlwaysAcceptReplayProtector());
        var context = CreateContext();

        var result = await validator.ValidateAsync(context, "corr-1", CancellationToken.None);

        Assert.False(result.Succeeded);
        Assert.Equal(TrustedGatewayFailureReason.MissingHeaders, result.FailureReason);
    }

    [Fact]
    public async Task ValidateAsync_should_fail_with_invalid_timestamp()
    {
        var options = CreateOptions();
        var validator = new TrustedGatewayRequestValidator(options, new AlwaysAcceptReplayProtector(), NullLogger<TrustedGatewayRequestValidator>.Instance);
        var context = CreateContext();

        context.Request.Headers[options.SignatureHeaderName] = "AA";
        context.Request.Headers[options.TimestampHeaderName] = "not-a-timestamp";
        context.Request.Headers[options.KeyIdHeaderName] = "k1";
        context.Request.Headers[options.SourceHeaderName] = options.Source;
        context.Request.Headers[options.NonceHeaderName] = "nonce";
        context.Request.Headers[options.ContentHashHeaderName] = "AA";

        var result = await validator.ValidateAsync(context, "corr-2", CancellationToken.None);

        Assert.False(result.Succeeded);
        Assert.Equal(TrustedGatewayFailureReason.InvalidTimestamp, result.FailureReason);
    }

    [Fact]
    public async Task ValidateAsync_should_fail_when_replay_is_detected()
    {
        var options = CreateOptions();
        var signer = new TrustedGatewaySigner(options);
        var validator = new TrustedGatewayRequestValidator(options, new AlwaysRejectReplayProtector(), NullLogger<TrustedGatewayRequestValidator>.Instance);
        var context = CreateContext();
        var signed = await signer.SignAsync(context.Request, "corr-3", CancellationToken.None);
        ApplySignedHeaders(context, options, signed);

        var result = await validator.ValidateAsync(context, "corr-3", CancellationToken.None);

        Assert.False(result.Succeeded);
        Assert.Equal(TrustedGatewayFailureReason.ReplayDetected, result.FailureReason);
    }

    private static TrustedGatewayRequestValidator CreateValidator(ITrustedGatewayReplayProtector replayProtector) =>
        new(CreateOptions(), replayProtector, NullLogger<TrustedGatewayRequestValidator>.Instance);

    private static TrustedGatewayOptions CreateOptions() =>
        new()
        {
            Source = "Norge360.ApiGateway",
            AllowedSources = ["Norge360.ApiGateway"],
            CurrentKeyId = "k1",
            Keys = [new TrustedGatewayKeyOptions { KeyId = "k1", Secret = "test-secret", Enabled = true, SignRequests = true }]
        };

    private static DefaultHttpContext CreateContext()
    {
        var context = new DefaultHttpContext();
        context.Request.Method = HttpMethods.Post;
        context.Request.Scheme = Uri.UriSchemeHttps;
        context.Request.Host = new HostString("gateway.norge360.internal");
        context.Request.Path = "/trusted-gateway/test";
        context.Request.ContentType = "application/json";
        context.Request.Body = new MemoryStream("""{"hello":"world"}"""u8.ToArray());
        context.Request.ContentLength = context.Request.Body.Length;
        return context;
    }

    private static void ApplySignedHeaders(DefaultHttpContext context, TrustedGatewayOptions options, TrustedGatewaySignedHeaders signed)
    {
        context.Request.Headers[options.SignatureHeaderName] = signed.Signature;
        context.Request.Headers[options.TimestampHeaderName] = signed.Timestamp;
        context.Request.Headers[options.KeyIdHeaderName] = signed.KeyId;
        context.Request.Headers[options.SourceHeaderName] = signed.Source;
        context.Request.Headers[options.NonceHeaderName] = signed.Nonce;
        context.Request.Headers[options.ContentHashHeaderName] = signed.ContentHash;
    }

    private sealed class AlwaysAcceptReplayProtector : ITrustedGatewayReplayProtector
    {
        public Task<bool> TryRegisterAsync(string keyId, string nonce, TimeSpan ttl, CancellationToken cancellationToken) => Task.FromResult(true);
    }

    private sealed class AlwaysRejectReplayProtector : ITrustedGatewayReplayProtector
    {
        public Task<bool> TryRegisterAsync(string keyId, string nonce, TimeSpan ttl, CancellationToken cancellationToken) => Task.FromResult(false);
    }
}
