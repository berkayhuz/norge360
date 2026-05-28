// <copyright file="HealthChecksBenchmarks.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using BenchmarkDotNet.Attributes;
using Microsoft.Extensions.Caching.Distributed;
using Microsoft.Extensions.Diagnostics.HealthChecks;
using Microsoft.Extensions.Options;
using Microsoft.IdentityModel.Tokens;
using Norge360.AspNetCore.TrustedGateway.Options;
using Norge360.Auth.API.Health;
using Norge360.Auth.Application.Abstractions;

namespace Norge360.Auth.Benchmarks;

[MemoryDiagnoser]
public class HealthChecksBenchmarks
{
    private readonly HealthCheckContext _context = new();
    private DistributedCacheAvailabilityHealthCheck _cacheHealthCheck = default!;
    private JwtSigningKeyHealthCheck _jwtSigningKeyHealthy = default!;
    private JwtSigningKeyHealthCheck _jwtSigningKeyUnhealthy = default!;
    private TrustedGatewayConfigurationHealthCheck _trustedGatewayDisabled = default!;
    private TrustedGatewayConfigurationHealthCheck _trustedGatewayMissingConfig = default!;

    [GlobalSetup]
    public void Setup()
    {
        _cacheHealthCheck = new DistributedCacheAvailabilityHealthCheck(new InMemoryDistributedCache());
        _jwtSigningKeyHealthy = new JwtSigningKeyHealthCheck(new TokenSigningKeyProviderStub("kid-1", [new SymmetricSecurityKey(new byte[32])]));
        _jwtSigningKeyUnhealthy = new JwtSigningKeyHealthCheck(new TokenSigningKeyProviderStub(string.Empty, []));
        _trustedGatewayDisabled = new TrustedGatewayConfigurationHealthCheck(
            Options.Create(new TrustedGatewayOptions { RequireTrustedGateway = false }));
        _trustedGatewayMissingConfig = new TrustedGatewayConfigurationHealthCheck(
            Options.Create(new TrustedGatewayOptions { RequireTrustedGateway = true, AllowedSources = [] }));
    }

    [Benchmark] public Task<HealthCheckResult> DistributedCache_Roundtrip() => _cacheHealthCheck.CheckHealthAsync(_context, CancellationToken.None);
    [Benchmark] public Task<HealthCheckResult> JwtSigningKey_Healthy() => _jwtSigningKeyHealthy.CheckHealthAsync(_context, CancellationToken.None);
    [Benchmark] public Task<HealthCheckResult> JwtSigningKey_Unhealthy() => _jwtSigningKeyUnhealthy.CheckHealthAsync(_context, CancellationToken.None);
    [Benchmark] public Task<HealthCheckResult> TrustedGateway_Disabled() => _trustedGatewayDisabled.CheckHealthAsync(_context, CancellationToken.None);
    [Benchmark] public Task<HealthCheckResult> TrustedGateway_MissingConfig() => _trustedGatewayMissingConfig.CheckHealthAsync(_context, CancellationToken.None);

    private sealed class TokenSigningKeyProviderStub(string currentKeyId, IReadOnlyCollection<SecurityKey> validationKeys) : ITokenSigningKeyProvider
    {
        public string CurrentKeyId => currentKeyId;
        public SigningCredentials GetCurrentSigningCredentials() => new(new SymmetricSecurityKey(new byte[32]), SecurityAlgorithms.HmacSha256);
        public IReadOnlyCollection<SecurityKey> GetValidationKeys() => validationKeys;
        public object GetJwksDocument(string issuer) => new { issuer, keys = validationKeys.Count };
    }

    private sealed class InMemoryDistributedCache : IDistributedCache
    {
        private readonly Dictionary<string, byte[]> _values = new(StringComparer.Ordinal);

        public byte[]? Get(string key) => _values.TryGetValue(key, out var value) ? value : null;
        public Task<byte[]?> GetAsync(string key, CancellationToken token = default) => Task.FromResult(Get(key));
        public void Refresh(string key) { }
        public Task RefreshAsync(string key, CancellationToken token = default) => Task.CompletedTask;
        public void Remove(string key) => _values.Remove(key);
        public Task RemoveAsync(string key, CancellationToken token = default)
        {
            Remove(key);
            return Task.CompletedTask;
        }

        public void Set(string key, byte[] value, DistributedCacheEntryOptions options) => _values[key] = value;
        public Task SetAsync(string key, byte[] value, DistributedCacheEntryOptions options, CancellationToken token = default)
        {
            Set(key, value, options);
            return Task.CompletedTask;
        }
    }
}
