// <copyright file="AuthTrustedGatewayOptionsValidationTests.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using Microsoft.Extensions.Hosting;
using Norge360.AspNetCore.TrustedGateway.Options;
using Norge360.Auth.API.Security;

namespace Norge360.Auth.Api.FunctionalTests.Security;

public sealed class AuthTrustedGatewayOptionsValidationTests
{
    [Fact]
    public void Validate_Should_Fail_When_RequireTrustedGateway_And_Keys_Missing()
    {
        var sut = new AuthTrustedGatewayOptionsValidation(new TestHostEnvironment(Environments.Development));
        var options = new TrustedGatewayOptions
        {
            RequireTrustedGateway = true,
            AllowedSources = ["Norge360.Account"]
        };

        var result = sut.Validate(name: null, options);

        Assert.False(result.Succeeded);
        Assert.NotNull(result.Failures);
        Assert.Contains(result.Failures, f => f.Contains("Keys must contain at least one key.", StringComparison.Ordinal));
    }

    [Fact]
    public void Validate_Should_Fail_When_Production_Secret_Is_Too_Short_And_Placeholder()
    {
        var sut = new AuthTrustedGatewayOptionsValidation(new TestHostEnvironment(Environments.Production));
        var options = CreateBaseOptions();
        options.Keys =
        [
            new TrustedGatewayKeyOptions
            {
                KeyId = "gateway-prod-key-2026-01",
                Secret = "DEV_SHORT",
                Enabled = true
            }
        ];
        options.AllowedGatewayProxies = ["10.10.10.10"];

        var result = sut.Validate(name: null, options);

        Assert.False(result.Succeeded);
        Assert.NotNull(result.Failures);
        Assert.Contains(result.Failures, f => f.Contains("Secret must be at least 32 characters", StringComparison.Ordinal));
        Assert.Contains(result.Failures, f => f.Contains("Secret contains a non-production placeholder marker", StringComparison.Ordinal));
    }

    [Fact]
    public void Validate_Should_Fail_When_Production_KeyId_Contains_Local_And_No_Gateway_Surface()
    {
        var sut = new AuthTrustedGatewayOptionsValidation(new TestHostEnvironment(Environments.Production));
        var options = CreateBaseOptions();
        options.Keys =
        [
            new TrustedGatewayKeyOptions
            {
                KeyId = "gateway-local-key-2026-01",
                Secret = "abcdefghijklmnopqrstuvwxyz0123456789",
                Enabled = true
            }
        ];

        var result = sut.Validate(name: null, options);

        Assert.False(result.Succeeded);
        Assert.NotNull(result.Failures);
        Assert.Contains(result.Failures, f => f.Contains("KeyId cannot be a local/dev/test identifier", StringComparison.Ordinal));
        Assert.Contains(result.Failures, f => f.Contains("must define at least one allowed gateway proxy or network in production", StringComparison.Ordinal));
    }

    [Fact]
    public void Validate_Should_Succeed_With_Production_Safe_Configuration()
    {
        var sut = new AuthTrustedGatewayOptionsValidation(new TestHostEnvironment(Environments.Production));
        var options = CreateBaseOptions();
        options.Keys =
        [
            new TrustedGatewayKeyOptions
            {
                KeyId = "gateway-prod-key-2026-01",
                Secret = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789",
                Enabled = true
            }
        ];
        options.AllowedGatewayNetworks = ["10.10.0.0/16"];

        var result = sut.Validate(name: null, options);

        Assert.True(result.Succeeded);
    }

    private static TrustedGatewayOptions CreateBaseOptions() => new()
    {
        RequireTrustedGateway = true,
        AllowedSources = ["Norge360.Account"],
        AllowedClockSkewSeconds = 30,
        ReplayProtectionWindowSeconds = 120
    };

    private sealed class TestHostEnvironment(string environmentName) : IHostEnvironment
    {
        public string EnvironmentName { get; set; } = environmentName;

        public string ApplicationName { get; set; } = "Norge360.Auth.Api.FunctionalTests";

        public string ContentRootPath { get; set; } = AppContext.BaseDirectory;

        public Microsoft.Extensions.FileProviders.IFileProvider ContentRootFileProvider { get; set; } =
            new Microsoft.Extensions.FileProviders.NullFileProvider();
    }
}
