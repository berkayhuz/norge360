// <copyright file="GatewayCorsOptionsValidationTests.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using FluentAssertions;
using Microsoft.Extensions.FileProviders;
using Microsoft.Extensions.Hosting;
using Norge360.ApiGateway.Options;

namespace Norge360.ApiGateway.UnitTests.Options;

public sealed class GatewayCorsOptionsValidationTests
{
    [Fact]
    public void Validate_Should_Accept_Production_Norge360_Origins()
    {
        var validator = new GatewayCorsOptionsValidation(new TestHostEnvironment(Environments.Production));

        var result = validator.Validate(
            null,
            new GatewayCorsOptions
            {
                AllowedOrigins =
                [
                    "https://Norge360.com",
                    "https://www.Norge360.com"
                ],
                AllowCredentials = true
            });

        result.Failed.Should().BeFalse();
    }

    [Fact]
    public void Validate_Should_Reject_Development_Origin_In_Production()
    {
        var validator = new GatewayCorsOptionsValidation(new TestHostEnvironment(Environments.Production));

        var result = validator.Validate(
            null,
            new GatewayCorsOptions
            {
                AllowedOrigins = ["http://localhost:7006"],
                AllowCredentials = true
            });

        result.Failed.Should().BeTrue();
        result.Failures.Should().Contain(message => message.Contains("loopback origin", StringComparison.Ordinal));
    }

    private sealed class TestHostEnvironment(string environmentName) : IHostEnvironment
    {
        public string EnvironmentName { get; set; } = environmentName;
        public string ApplicationName { get; set; } = "Norge360.ApiGateway.UnitTests";
        public string ContentRootPath { get; set; } = AppContext.BaseDirectory;
        public IFileProvider ContentRootFileProvider { get; set; } = new NullFileProvider();
    }
}
