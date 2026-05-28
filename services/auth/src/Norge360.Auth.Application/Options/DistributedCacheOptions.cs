// <copyright file="DistributedCacheOptions.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

namespace Norge360.Auth.Application.Options;

public sealed class DistributedCacheOptions
{
    public const string SectionName = "Infrastructure:DistributedCache";

    public string Provider { get; set; } = "Redis";

    public string? RedisConnectionString { get; set; }

    public string InstanceName { get; set; } = "Norge360:Auth:";

    public int ConnectTimeoutMilliseconds { get; set; } = 5000;

    public int AsyncTimeoutMilliseconds { get; set; } = 5000;

    public int SyncTimeoutMilliseconds { get; set; } = 5000;

    public int ConnectRetry { get; set; } = 3;

    public bool AbortOnConnectFail { get; set; }

    public bool RequireExternalProviderInProduction { get; set; } = true;
}
