// <copyright file="TrustedGatewayBenchmarks.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using BenchmarkDotNet.Attributes;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Logging.Abstractions;
using Norge360.AspNetCore.TrustedGateway.Abstractions;
using Norge360.AspNetCore.TrustedGateway.Options;
using Norge360.AspNetCore.TrustedGateway.Signing;
using Norge360.AspNetCore.TrustedGateway.Validation;

namespace Norge360.AspNetCore.Benchmarks;

[MemoryDiagnoser]
public class TrustedGatewayBenchmarks
{
    private const string CorrelationId = "bench-correlation-id";
    private readonly TrustedGatewayOptions _options = new()
    {
        Source = "Norge360.ApiGateway",
        CurrentKeyId = "k1",
        AllowedSources = ["Norge360.ApiGateway"],
        Keys = [new TrustedGatewayKeyOptions { KeyId = "k1", Secret = "benchmark-secret", Enabled = true, SignRequests = true }]
    };

    private readonly ITrustedGatewayReplayProtector _replayProtector = new NoopReplayProtector();
    private TrustedGatewaySigner _signer = null!;
    private TrustedGatewayRequestValidator _validator = null!;
    private DefaultHttpContext _context = null!;

    [GlobalSetup]
    public void Setup()
    {
        _signer = new TrustedGatewaySigner(_options);
        _validator = new TrustedGatewayRequestValidator(
            _options,
            _replayProtector,
            NullLogger<TrustedGatewayRequestValidator>.Instance);

        _context = CreateContext();
    }

    [Benchmark]
    public Task<string> ComputeBodyHash() => TrustedGatewayCanonicalRequest.ComputeBodyHashAsync(_context.Request, CancellationToken.None);

    [Benchmark]
    public Task SignRequest() => _signer.SignAsync(_context.Request, CorrelationId, CancellationToken.None);

    [Benchmark]
    public async Task ValidateRequest()
    {
        _context = CreateContext();
        var signed = await _signer.SignAsync(_context.Request, CorrelationId, CancellationToken.None);

        _context.Request.Headers[_options.SignatureHeaderName] = signed.Signature;
        _context.Request.Headers[_options.TimestampHeaderName] = signed.Timestamp;
        _context.Request.Headers[_options.KeyIdHeaderName] = signed.KeyId;
        _context.Request.Headers[_options.SourceHeaderName] = signed.Source;
        _context.Request.Headers[_options.NonceHeaderName] = signed.Nonce;
        _context.Request.Headers[_options.ContentHashHeaderName] = signed.ContentHash;

        _ = await _validator.ValidateAsync(_context, CorrelationId, CancellationToken.None);
    }

    private static DefaultHttpContext CreateContext()
    {
        var context = new DefaultHttpContext();
        context.Request.Method = HttpMethods.Post;
        context.Request.Scheme = Uri.UriSchemeHttps;
        context.Request.Host = new HostString("gateway.norge360.internal");
        context.Request.Path = "/trusted-gateway/bench";
        context.Request.QueryString = new QueryString("?a=1&b=2");
        context.Request.ContentType = "application/json";
        context.Request.Body = new MemoryStream("""{"hello":"world"}"""u8.ToArray());
        context.Request.ContentLength = context.Request.Body.Length;
        context.Connection.RemoteIpAddress = System.Net.IPAddress.Parse("127.0.0.1");
        return context;
    }

    private sealed class NoopReplayProtector : ITrustedGatewayReplayProtector
    {
        public Task<bool> TryRegisterAsync(string keyId, string nonce, TimeSpan ttl, CancellationToken cancellationToken) => Task.FromResult(true);
    }
}
