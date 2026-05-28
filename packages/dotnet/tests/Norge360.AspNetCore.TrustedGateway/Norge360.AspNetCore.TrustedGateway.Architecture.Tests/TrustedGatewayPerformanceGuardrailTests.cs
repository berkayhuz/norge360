// <copyright file="TrustedGatewayPerformanceGuardrailTests.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Logging.Abstractions;
using Norge360.AspNetCore.TrustedGateway.Abstractions;
using Norge360.AspNetCore.TrustedGateway.Options;
using Norge360.AspNetCore.TrustedGateway.Signing;
using Norge360.AspNetCore.TrustedGateway.Validation;

namespace Norge360.AspNetCore.TrustedGateway.Architecture.Tests;

public class TrustedGatewayPerformanceGuardrailTests
{
    private const int IterationCount = 250;

    [Fact]
    [Trait("Category", "PerformanceGuardrail")]
    public async Task ValidateAsync_allocation_should_remain_within_budget()
    {
        var options = CreateOptions();
        var signer = new TrustedGatewaySigner(options);
        var validator = new TrustedGatewayRequestValidator(options, new AlwaysAcceptReplayProtector(), NullLogger<TrustedGatewayRequestValidator>.Instance);

        var bytesPerOperation = await MeasureAllocatedBytesPerOperationAsync(async () =>
        {
            var context = CreateContext();
            var signed = await signer.SignAsync(context.Request, "corr-guardrail", CancellationToken.None);
            context.Request.Headers[options.SignatureHeaderName] = signed.Signature;
            context.Request.Headers[options.TimestampHeaderName] = signed.Timestamp;
            context.Request.Headers[options.KeyIdHeaderName] = signed.KeyId;
            context.Request.Headers[options.SourceHeaderName] = signed.Source;
            context.Request.Headers[options.NonceHeaderName] = signed.Nonce;
            context.Request.Headers[options.ContentHashHeaderName] = signed.ContentHash;
            _ = await validator.ValidateAsync(context, "corr-guardrail", CancellationToken.None);
        });

        Assert.True(
            bytesPerOperation <= 11_000,
            $"TrustedGateway ValidateAsync allocation budget exceeded. Measured {bytesPerOperation} bytes/op, expected <= 11000 bytes/op.");
    }

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
        context.Request.Path = "/trusted-gateway/guardrail";
        context.Request.ContentType = "application/json";
        context.Request.Body = new MemoryStream("""{"hello":"world"}"""u8.ToArray());
        context.Request.ContentLength = context.Request.Body.Length;
        return context;
    }

    private static async Task<long> MeasureAllocatedBytesPerOperationAsync(Func<Task> action)
    {
        for (var i = 0; i < 25; i++)
        {
            await action();
        }

        GC.Collect();
        GC.WaitForPendingFinalizers();
        GC.Collect();

        var before = GC.GetAllocatedBytesForCurrentThread();
        for (var i = 0; i < IterationCount; i++)
        {
            await action();
        }

        var totalAllocated = GC.GetAllocatedBytesForCurrentThread() - before;
        return totalAllocated / IterationCount;
    }

    private sealed class AlwaysAcceptReplayProtector : ITrustedGatewayReplayProtector
    {
        public Task<bool> TryRegisterAsync(string keyId, string nonce, TimeSpan ttl, CancellationToken cancellationToken) => Task.FromResult(true);
    }
}
