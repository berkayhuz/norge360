// <copyright file="NotificationEmailSecurityTests.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using Amazon.SimpleEmailV2;
using Amazon.SimpleEmailV2.Model;
using FluentAssertions;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using Moq;
using Norge360.Notification.Infrastructure.DependencyInjection;
using Norge360.Notification.Infrastructure.Modules.Email.Application;
using Norge360.Notification.Infrastructure.Modules.Email.Infrastructure.Options;
using Norge360.Notification.Infrastructure.Modules.Email.Infrastructure.Providers;

namespace Norge360.Notification.UnitTests.Email;

public sealed class NotificationEmailSecurityTests
{
    [Fact]
    public void Production_Should_Fail_When_EmailProvider_Is_Disabled()
    {
        var validator = new NotificationEmailProviderOptionsValidation(new FakeHostEnvironment(Environments.Production));

        var result = validator.Validate(null, new EmailProviderOptions { Provider = "disabled" });

        result.Failed.Should().BeTrue();
    }

    [Fact]
    public void DisabledProvider_Should_Be_Allowed_Only_In_Development_Test()
    {
        var validator = new NotificationEmailProviderOptionsValidation(new FakeHostEnvironment(Environments.Development));

        var result = validator.Validate(null, new EmailProviderOptions { Provider = "disabled" });

        result.Succeeded.Should().BeTrue();
    }

    [Fact]
    public void Production_Should_Fail_When_FromAddress_Is_Not_Approved()
    {
        var providerOptions = Options.Create(new EmailProviderOptions
        {
            Provider = "smtp",
            ApprovedSenderDomains = ["norge360.com"]
        });

        var validator = new SmtpEmailProviderOptionsValidation(
            new FakeHostEnvironment(Environments.Production),
            providerOptions);

        var result = validator.Validate(null, new SmtpEmailProviderOptions
        {
            Host = "smtp.example.net",
            Port = 587,
            FromAddress = "attacker@untrusted.example",
            FromName = "Malicious",
            UserName = "mailer",
            Password = "not-used-in-output",
            UseStartTls = true
        });

        result.Failed.Should().BeTrue();
        result.Failures.Should().Contain(message =>
            message.Contains("approved sender domain", StringComparison.OrdinalIgnoreCase));
    }

    [Fact]
    public async Task Ses_Provider_Should_Map_Subject_Html_Text_From_To_Correctly()
    {
        SendEmailRequest? captured = null;
        var sesClient = new Mock<IAmazonSimpleEmailServiceV2>();
        sesClient.Setup(client => client.SendEmailAsync(It.IsAny<SendEmailRequest>(), It.IsAny<CancellationToken>()))
            .Callback<SendEmailRequest, CancellationToken>((request, _) => captured = request)
            .ReturnsAsync(new SendEmailResponse { MessageId = "ses-message-id" });

        var provider = new AmazonSesEmailProvider(
            sesClient.Object,
            Options.Create(new AmazonSesEmailProviderOptions
            {
                Region = "eu-central-1",
                FromAddress = "notifications@norge360.com",
                FromName = "Norge360 Notifications",
                ConfigurationSetName = "norge360-email"
            }),
            LoggerFactory.Create(builder => { }).CreateLogger<AmazonSesEmailProvider>());

        await provider.SendAsync(
            new EmailMessage(
                "alice@example.com",
                "Reset your password",
                "<p>Hello</p>",
                "Hello",
                "corr-123"),
            CancellationToken.None);

        captured.Should().NotBeNull();
        captured!.FromEmailAddress.Should().Contain("notifications@norge360.com");
        captured.Destination.ToAddresses.Should().ContainSingle("alice@example.com");
        captured.Content.Simple.Subject.Data.Should().Be("Reset your password");
        captured.Content.Simple.Body.Html.Data.Should().Be("<p>Hello</p>");
        captured.Content.Simple.Body.Text.Data.Should().Be("Hello");
    }

    [Fact]
    public async Task Reset_Link_Should_Not_Be_Logged()
    {
        const string resetLink = "https://app.example/reset?token=raw-reset-token";
        var sink = new InMemoryLoggerProvider();
        using var loggerFactory = LoggerFactory.Create(builder => builder.AddProvider(sink));

        var sesClient = new Mock<IAmazonSimpleEmailServiceV2>();
        sesClient.Setup(client => client.SendEmailAsync(It.IsAny<SendEmailRequest>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(new SendEmailResponse { MessageId = "ses-message-id" });

        var provider = new AmazonSesEmailProvider(
            sesClient.Object,
            Options.Create(new AmazonSesEmailProviderOptions
            {
                Region = "eu-central-1",
                FromAddress = "notifications@norge360.com",
                FromName = "Norge360 Notifications"
            }),
            loggerFactory.CreateLogger<AmazonSesEmailProvider>());

        await provider.SendAsync(
            new EmailMessage(
                "alice@example.com",
                "Reset",
                $"<a href=\"{resetLink}\">reset</a>",
                $"Reset: {resetLink}",
                "corr-456"),
            CancellationToken.None);

        sink.Messages.Should().NotContain(message => message.Contains("raw-reset-token", StringComparison.Ordinal));
        sink.Messages.Should().NotContain(message => message.Contains(resetLink, StringComparison.Ordinal));
    }

    [Fact]
    public void Smtp_Provider_Should_Not_Log_Password()
    {
        var providerOptions = Options.Create(new EmailProviderOptions
        {
            Provider = "smtp",
            ApprovedSenderDomains = ["norge360.com"]
        });

        var validator = new SmtpEmailProviderOptionsValidation(
            new FakeHostEnvironment(Environments.Production),
            providerOptions);

        var result = validator.Validate(null, new SmtpEmailProviderOptions
        {
            Host = "smtp.example.net",
            Port = 587,
            FromAddress = "notifications@norge360.com",
            FromName = "Norge360 Notifications",
            UserName = "mailer-user",
            Password = "VerySecretPasswordValue123!",
            UseStartTls = false
        });

        result.Failed.Should().BeTrue();
        result.Failures.Should().NotContain(message =>
            message.Contains("VerySecretPasswordValue123!", StringComparison.Ordinal));
    }

    [Fact]
    public void Notifications_Sender_Should_Be_Default_For_Auth_Mails()
    {
        var smtp = new SmtpEmailProviderOptions();
        var ses = new AmazonSesEmailProviderOptions();

        smtp.FromAddress.Should().Be("notifications@norge360.com");
        ses.FromAddress.Should().Be("notifications@norge360.com");
    }

    private sealed class FakeHostEnvironment(string environmentName) : IHostEnvironment
    {
        public string EnvironmentName { get; set; } = environmentName;
        public string ApplicationName { get; set; } = "Norge360.Notification.UnitTests";
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
