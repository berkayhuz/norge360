// <copyright file="GatewayTenantForwardingOptionsValidationTests.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using FluentAssertions;
using Microsoft.Extensions.FileProviders;
using Microsoft.Extensions.Hosting;
using Norge360.ApiGateway.Options;

namespace Norge360.ApiGateway.UnitTests.Options;

public sealed class GatewayTenantForwardingOptionsValidationTests
{
    [Fact]
    public void Validate_Should_Fail_In_Production_When_Default_Static_Tenant_Is_Configured()
    {
        var validator = new GatewayTenantForwardingOptionsValidation(new TestHostEnvironment(Environments.Production));

        var result = validator.Validate(
            null,
            new GatewayTenantForwardingOptions
            {
                StaticTenantId = Guid.Parse("11111111-1111-1111-1111-111111111111"),
                TrustedHostSuffixes = ["Norge360.com"]
            });

        result.Failed.Should().BeTrue();
        result.Failures.Should().Contain(message => message.Contains("default development tenant id", StringComparison.Ordinal));
    }

    [Fact]
    public void Validate_Should_Still_Fail_In_Production_When_Default_Static_Tenant_Is_Explicitly_Allowed()
    {
        var validator = new GatewayTenantForwardingOptionsValidation(new TestHostEnvironment(Environments.Production));

        var result = validator.Validate(
            null,
            new GatewayTenantForwardingOptions
            {
                AllowStaticTenantIdInProduction = true,
                StaticTenantId = Guid.Parse("11111111-1111-1111-1111-111111111111"),
                TrustedHostSuffixes = ["Norge360.com"]
            });

        result.Failed.Should().BeTrue();
        result.Failures.Should().Contain(message => message.Contains("default development tenant id", StringComparison.Ordinal));
    }

    [Fact]
    public void Validate_Should_Fail_In_Production_When_Static_Tenant_Is_Not_Explicitly_Allowed()
    {
        var validator = new GatewayTenantForwardingOptionsValidation(new TestHostEnvironment(Environments.Production));

        var result = validator.Validate(
            null,
            new GatewayTenantForwardingOptions
            {
                StaticTenantId = Guid.NewGuid()
            });

        result.Failed.Should().BeTrue();
        result.Failures.Should().Contain(message => message.Contains("AllowStaticTenantIdInProduction", StringComparison.Ordinal));
    }

    [Fact]
    public void Validate_Should_Pass_In_Production_When_Tenant_Is_Resolved_From_Trusted_Host_Suffix()
    {
        var validator = new GatewayTenantForwardingOptionsValidation(new TestHostEnvironment(Environments.Production));

        var result = validator.Validate(
            null,
            new GatewayTenantForwardingOptions
            {
                TrustedHostSuffixes = ["Norge360.com"]
            });

        result.Failed.Should().BeFalse();
    }

    [Fact]
    public void Validate_Should_Pass_In_Production_When_NonDefault_Static_Tenant_Is_Explicitly_Allowed()
    {
        var validator = new GatewayTenantForwardingOptionsValidation(new TestHostEnvironment(Environments.Production));

        var result = validator.Validate(
            null,
            new GatewayTenantForwardingOptions
            {
                AllowStaticTenantIdInProduction = true,
                StaticTenantId = Guid.NewGuid()
            });

        result.Failed.Should().BeFalse();
    }

    [Fact]
    public void Validate_Should_Allow_Static_Tenant_In_Development()
    {
        var validator = new GatewayTenantForwardingOptionsValidation(new TestHostEnvironment(Environments.Development));

        var result = validator.Validate(
            null,
            new GatewayTenantForwardingOptions
            {
                StaticTenantId = Guid.Parse("11111111-1111-1111-1111-111111111111")
            });

        result.Failed.Should().BeFalse();
    }

    private sealed class TestHostEnvironment(string environmentName) : IHostEnvironment
    {
        public string EnvironmentName { get; set; } = environmentName;
        public string ApplicationName { get; set; } = "Norge360.ApiGateway.UnitTests";
        public string ContentRootPath { get; set; } = AppContext.BaseDirectory;
        public IFileProvider ContentRootFileProvider { get; set; } = new NullFileProvider();
    }
}
