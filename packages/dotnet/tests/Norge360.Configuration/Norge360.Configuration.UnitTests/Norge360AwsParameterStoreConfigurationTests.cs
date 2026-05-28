// <copyright file="Norge360AwsParameterStoreConfigurationTests.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using Amazon.SimpleSystemsManagement;
using Amazon.SimpleSystemsManagement.Model;
using FluentAssertions;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Moq;
using Norge360.Configuration.AwsParameterStore;

namespace Norge360.Configuration.UnitTests;

public sealed class Norge360AwsParameterStoreConfigurationTests
{
    [Fact]
    public void ParameterNameMapping_Should_Map_Hierarchical_Paths_To_ConfigurationKeys()
    {
        var mapped = Norge360AwsParameterNameMapper.Map(
            "/norge360/production/notification/email/smtp/password",
            "placeholder",
            "/norge360/production");

        mapped.Should().ContainKey("Notification:Email:Smtp:Password");
    }

    [Fact]
    public void Configuration_Should_Load_From_ParameterStore_When_Enabled()
    {
        var configuration = new ConfigurationManager();
        configuration.AddInMemoryCollection(new Dictionary<string, string?>
        {
            ["Infrastructure:AwsParameterStore:Enabled"] = "true",
            ["Infrastructure:AwsParameterStore:OptionalWhenEnabled"] = "false",
            ["Infrastructure:AwsParameterStore:ParameterPathPrefix"] = "/norge360/{environment}"
        });

        var ssmClient = new Mock<IAmazonSimpleSystemsManagement>(MockBehavior.Strict);
        ssmClient.As<IDisposable>().Setup(client => client.Dispose());
        ssmClient.Setup(client => client.GetParametersByPathAsync(
                It.IsAny<GetParametersByPathRequest>(),
                It.IsAny<CancellationToken>()))
            .ReturnsAsync(new GetParametersByPathResponse
            {
                NextToken = null,
                Parameters =
                [
                    new Parameter
                    {
                        Name = "/norge360/development/auth/database/connection-string",
                        Value = "Host=dev-db.internal;Port=5432;Database=auth;Username=auth_app;Password=test-only-placeholder;SSL Mode=Require;Trust Server Certificate=true"
                    }
                ]
            });

        configuration.AddNorge360AwsParameterStore(
            new FakeHostEnvironment(Environments.Development),
            clientFactory: _ => ssmClient.Object);

        configuration.GetConnectionString("IdentityConnection").Should().Be("Host=dev-db.internal;Port=5432;Database=auth;Username=auth_app;Password=test-only-placeholder;SSL Mode=Require;Trust Server Certificate=true");
    }

    [Fact]
    public void Configuration_Should_Not_Log_Secret_Values_When_Load_Fails()
    {
        const string secretMarker = "raw-secret-value-should-not-appear";
        var sink = new InMemoryLoggerProvider();
        using var loggerFactory = LoggerFactory.Create(builder => builder.AddProvider(sink));

        var configuration = new ConfigurationManager();
        configuration.AddInMemoryCollection(new Dictionary<string, string?>
        {
            ["Infrastructure:AwsParameterStore:Enabled"] = "true",
            ["Infrastructure:AwsParameterStore:OptionalWhenEnabled"] = "true",
            ["Infrastructure:AwsParameterStore:ParameterPathPrefix"] = "/norge360/{environment}"
        });

        var ssmClient = new Mock<IAmazonSimpleSystemsManagement>(MockBehavior.Strict);
        ssmClient.As<IDisposable>().Setup(client => client.Dispose());
        ssmClient.Setup(client => client.GetParametersByPathAsync(
                It.IsAny<GetParametersByPathRequest>(),
                It.IsAny<CancellationToken>()))
            .ThrowsAsync(new InvalidOperationException(secretMarker));

        configuration.AddNorge360AwsParameterStore(
            new FakeHostEnvironment(Environments.Development),
            loggerFactory: loggerFactory,
            clientFactory: _ => ssmClient.Object);

        sink.Messages.Should().NotContain(message => message.Contains(secretMarker, StringComparison.Ordinal));
    }

    [Fact]
    public void Production_Should_Fail_When_Required_Secret_Is_Missing()
    {
        var configuration = new ConfigurationManager();
        configuration.AddInMemoryCollection(new Dictionary<string, string?>
        {
            ["Infrastructure:AwsParameterStore:Enabled"] = "true",
            ["Infrastructure:AwsParameterStore:OptionalWhenEnabled"] = "true",
            ["Infrastructure:AwsParameterStore:RequireInProduction"] = "true",
            ["Infrastructure:AwsParameterStore:ParameterPathPrefix"] = "/norge360/{environment}",
            ["Infrastructure:AwsParameterStore:RequiredConfigurationKeys:0"] = "ConnectionStrings:IdentityConnection"
        });

        var ssmClient = new Mock<IAmazonSimpleSystemsManagement>(MockBehavior.Strict);
        ssmClient.As<IDisposable>().Setup(client => client.Dispose());
        ssmClient.Setup(client => client.GetParametersByPathAsync(
                It.IsAny<GetParametersByPathRequest>(),
                It.IsAny<CancellationToken>()))
            .ReturnsAsync(new GetParametersByPathResponse
            {
                NextToken = null,
                Parameters = []
            });

        var action = () => configuration.AddNorge360AwsParameterStore(
            new FakeHostEnvironment(Environments.Production),
            clientFactory: _ => ssmClient.Object);

        action.Should().Throw<InvalidOperationException>();
    }

    [Fact]
    public void Development_Should_Allow_Local_Fallback_When_Ssm_Is_Disabled()
    {
        var configuration = new ConfigurationManager();
        configuration.AddInMemoryCollection(new Dictionary<string, string?>
        {
            ["Infrastructure:AwsParameterStore:Enabled"] = "false",
            ["Infrastructure:AwsParameterStore:RequireInProduction"] = "true",
            ["ConnectionStrings:IdentityConnection"] = "Host=local-db.internal;Port=5432;Database=auth;Username=auth_app;Password=test-only-placeholder;SSL Mode=Require;Trust Server Certificate=true"
        });

        configuration.AddNorge360AwsParameterStore(new FakeHostEnvironment(Environments.Development));

        configuration.GetConnectionString("IdentityConnection").Should().Be("Host=local-db.internal;Port=5432;Database=auth;Username=auth_app;Password=test-only-placeholder;SSL Mode=Require;Trust Server Certificate=true");
    }

    private sealed class FakeHostEnvironment(string environmentName) : IHostEnvironment
    {
        public string EnvironmentName { get; set; } = environmentName;
        public string ApplicationName { get; set; } = "Norge360.Tests";
        public string ContentRootPath { get; set; } = AppContext.BaseDirectory;
        public Microsoft.Extensions.FileProviders.IFileProvider ContentRootFileProvider { get; set; } = null!;
    }

    private sealed class InMemoryLoggerProvider : ILoggerProvider
    {
        public List<string> Messages { get; } = [];

        public ILogger CreateLogger(string categoryName) => new InMemoryLogger(Messages);

        public void Dispose()
        {
        }
    }

    private sealed class InMemoryLogger(List<string> messages) : ILogger
    {
        public IDisposable BeginScope<TState>(TState state)
            where TState : notnull => NullDisposable.Instance;

        public bool IsEnabled(LogLevel logLevel) => true;

        public void Log<TState>(
            LogLevel logLevel,
            EventId eventId,
            TState state,
            Exception? exception,
            Func<TState, Exception?, string> formatter)
        {
            messages.Add(formatter(state, exception));
        }
    }

    private sealed class NullDisposable : IDisposable
    {
        public static readonly NullDisposable Instance = new();

        public void Dispose()
        {
        }
    }
}
