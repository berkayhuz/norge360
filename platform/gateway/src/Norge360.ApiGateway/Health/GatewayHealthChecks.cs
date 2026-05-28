// <copyright file="GatewayHealthChecks.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using Microsoft.Extensions.Diagnostics.HealthChecks;
using Microsoft.Extensions.Options;
using Norge360.AspNetCore.TrustedGateway.Options;
using Yarp.ReverseProxy.Configuration;

namespace Norge360.ApiGateway.Health;

public sealed class GatewaySigningConfigurationHealthCheck(IOptions<TrustedGatewayOptions> options) : IHealthCheck
{
    public Task<HealthCheckResult> CheckHealthAsync(HealthCheckContext context, CancellationToken cancellationToken = default)
    {
        var value = options.Value;
        var currentKey = value.Keys.FirstOrDefault(
            x => x.Enabled &&
                 x.SignRequests &&
                 string.Equals(x.KeyId, value.CurrentKeyId, StringComparison.Ordinal));

        return Task.FromResult(
            currentKey is null || string.IsNullOrWhiteSpace(currentKey.Secret)
                ? HealthCheckResult.Unhealthy("Trusted gateway signing key is unavailable.")
                : HealthCheckResult.Healthy("Trusted gateway signing key is available."));
    }
}

public sealed class GatewayReverseProxyConfigurationHealthCheck(IProxyConfigProvider proxyConfigProvider) : IHealthCheck
{
    public Task<HealthCheckResult> CheckHealthAsync(HealthCheckContext context, CancellationToken cancellationToken = default)
    {
        var config = proxyConfigProvider.GetConfig();
        if (config.Routes.Count == 0 || config.Clusters.Count == 0)
        {
            return Task.FromResult(HealthCheckResult.Unhealthy("Reverse proxy routes or clusters are not configured."));
        }

        return Task.FromResult(HealthCheckResult.Healthy("Reverse proxy configuration loaded."));
    }
}
