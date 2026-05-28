// <copyright file="OutboxSecurityIntegrationTests.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using System.Text.Json;
using FluentAssertions;
using Microsoft.AspNetCore.DataProtection;
using Microsoft.Data.Sqlite;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;
using Norge360.Auth.Application.Options;
using Norge360.Auth.Contracts.IntegrationEvents;
using Norge360.Auth.Domain.Entities;
using Norge360.Auth.Infrastructure.Persistence;
using Norge360.Auth.Infrastructure.Services;
using Norge360.Auth.TestKit.Builders;
using Norge360.Auth.TestKit.Fakes;
using Norge360.Messaging.Abstractions;
using Norge360.Messaging.RabbitMq.Options;

namespace Norge360.Auth.Infrastructure.IntegrationTests.Persistence;

public sealed class OutboxSecurityIntegrationTests
{
    [Fact]
    public async Task IntegrationEventOutbox_When_LifecyclePayloadContainsRawToken_Should_Protect_StoredPayload()
    {
        await using var fixture = await SqliteFixture.CreateAsync();
        var payloadProtector = CreatePayloadProtector();
        var outbox = new IntegrationEventOutbox(fixture.Context, payloadProtector);
        const string rawToken = "raw-lifecycle-token-never-store";
        var emailConfirmationUrl = $"https://app.example.test/confirm?token={rawToken}";
        var resetUrl = $"https://app.example.test/reset?token={rawToken}";
        var emailChangeUrl = $"https://app.example.test/email-change?token={rawToken}";

        await AddEventAsync(
            outbox,
            AuthEmailConfirmationRequestedV1.EventName,
            AuthEmailConfirmationRequestedV1.EventVersion,
            AuthEmailConfirmationRequestedV1.RoutingKey,
            new AuthEmailConfirmationRequestedV1(Guid.NewGuid(), Guid.NewGuid(), "alice", "alice@example.com", rawToken, emailConfirmationUrl, Utc(30)));
        await AddEventAsync(
            outbox,
            AuthPasswordResetRequestedV1.EventName,
            AuthPasswordResetRequestedV1.EventVersion,
            AuthPasswordResetRequestedV1.RoutingKey,
            new AuthPasswordResetRequestedV1(Guid.NewGuid(), Guid.NewGuid(), "alice", "alice@example.com", rawToken, resetUrl, Utc(30)));
        await AddEventAsync(
            outbox,
            AuthEmailChangeRequestedV1.EventName,
            AuthEmailChangeRequestedV1.EventVersion,
            AuthEmailChangeRequestedV1.RoutingKey,
            new AuthEmailChangeRequestedV1(Guid.NewGuid(), Guid.NewGuid(), "alice", "alice@example.com", "alice.new@example.com", rawToken, emailChangeUrl, Utc(30)));
        await fixture.Context.SaveChangesAsync();

        var messages = await fixture.Context.OutboxMessages.OrderBy(x => x.EventName).ToArrayAsync();

        messages.Should().HaveCount(3);
        foreach (var message in messages)
        {
            message.Payload.Should().StartWith(OutboxPayloadProtector.ProtectedPayloadPrefix);
            message.Payload.Should().NotContain(rawToken);
            payloadProtector.UnprotectForPublish(message.Payload).Should().Contain(rawToken);
        }
    }

    [Fact]
    public async Task IntegrationEventOutbox_When_InviteNotificationContainsRawTokenUrl_Should_Protect_StoredPayload()
    {
        await using var fixture = await SqliteFixture.CreateAsync();
        var payloadProtector = CreatePayloadProtector();
        var outbox = new IntegrationEventOutbox(fixture.Context, payloadProtector);
        const string invitationUrl = "https://app.example.test/invite?token=raw-invite-token-never-store";
        var payload = new
        {
            template = "auth.tenant_invitation.v1",
            metadata = new Dictionary<string, string> { ["invitationUrl"] = invitationUrl }
        };

        await outbox.AddAsync(
            Guid.NewGuid(),
            "notification.requested",
            1,
            "notification.requested.v1",
            "Norge360.Auth",
            payload,
            null,
            null,
            Utc(0),
            CancellationToken.None);
        await fixture.Context.SaveChangesAsync();

        var message = await fixture.Context.OutboxMessages.SingleAsync();

        message.Payload.Should().StartWith(OutboxPayloadProtector.ProtectedPayloadPrefix);
        message.Payload.Should().NotContain("raw-invite-token-never-store");
        payloadProtector.UnprotectForPublish(message.Payload).Should().Contain(invitationUrl);
    }

    [Fact]
    public async Task OutboxMessagePublisher_When_PayloadIsProtected_Should_Publish_UnprotectedPayload_And_Keep_StoredPayload_Protected()
    {
        await using var fixture = await SqliteFixture.CreateAsync();
        var payloadProtector = CreatePayloadProtector();
        var publisher = new CapturingIntegrationEventPublisher();
        const string rawToken = "raw-confirm-token-for-publish";
        var serializedPayload = JsonSerializer.Serialize(
            new AuthEmailConfirmationRequestedV1(Guid.NewGuid(), Guid.NewGuid(), "alice", "alice@example.com", rawToken, $"https://app.example.test/confirm?token={rawToken}", Utc(30)),
            new JsonSerializerOptions(JsonSerializerDefaults.Web));
        var message = new OutboxMessage
        {
            EventId = Guid.NewGuid(),
            EventName = AuthEmailConfirmationRequestedV1.EventName,
            EventVersion = AuthEmailConfirmationRequestedV1.EventVersion,
            Source = "Norge360.Auth",
            RoutingKey = AuthEmailConfirmationRequestedV1.RoutingKey,
            Payload = payloadProtector.ProtectForStorage(AuthEmailConfirmationRequestedV1.EventName, serializedPayload),
            OccurredAtUtc = Utc(0),
            CreatedAtUtc = Utc(0),
            NextAttemptAtUtc = Utc(0)
        };
        fixture.Context.OutboxMessages.Add(message);
        await fixture.Context.SaveChangesAsync();

        var batchPublisher = new OutboxMessagePublisher(
            fixture.Context,
            publisher,
            payloadProtector,
            Options.Create(new OutboxOptions { BatchSize = 10, MaxAttempts = 3, LockSeconds = 30 }),
            Options.Create(new RabbitMqOptions { Exchange = "auth-tests" }),
            new FakeClock(new DateTimeOffset(Utc(1), TimeSpan.Zero)),
            NullLogger<OutboxMessagePublisher>.Instance);

        var publishedCount = await batchPublisher.PublishBatchAsync(CancellationToken.None);

        publishedCount.Should().Be(1);
        publisher.Messages.Should().ContainSingle();
        publisher.Messages[0].Payload.Should().Contain(rawToken);

        var stored = await fixture.Context.OutboxMessages.AsNoTracking().SingleAsync();
        stored.PublishedAtUtc.Should().Be(Utc(1));
        stored.Payload.Should().StartWith(OutboxPayloadProtector.ProtectedPayloadPrefix);
        stored.Payload.Should().NotContain(rawToken);
    }

    [Fact]
    public async Task OutboxMessagePublisher_When_ProtectedPayloadCannotBeDecrypted_Should_FailClosed_Without_LeakingPayload()
    {
        await using var fixture = await SqliteFixture.CreateAsync();
        var payloadProtector = CreatePayloadProtector();
        var publisher = new CapturingIntegrationEventPublisher();
        var logger = new CapturingLogger<OutboxMessagePublisher>();
        const string invalidProtectedPayload = "not-valid-protected-data-raw-token-secret";
        var message = new OutboxMessage
        {
            EventId = Guid.NewGuid(),
            EventName = AuthPasswordResetRequestedV1.EventName,
            EventVersion = AuthPasswordResetRequestedV1.EventVersion,
            Source = "Norge360.Auth",
            RoutingKey = AuthPasswordResetRequestedV1.RoutingKey,
            Payload = OutboxPayloadProtector.ProtectedPayloadPrefix + invalidProtectedPayload,
            OccurredAtUtc = Utc(0),
            CreatedAtUtc = Utc(0),
            NextAttemptAtUtc = Utc(0)
        };
        fixture.Context.OutboxMessages.Add(message);
        await fixture.Context.SaveChangesAsync();

        var batchPublisher = new OutboxMessagePublisher(
            fixture.Context,
            publisher,
            payloadProtector,
            Options.Create(new OutboxOptions { BatchSize = 10, MaxAttempts = 3, LockSeconds = 30 }),
            Options.Create(new RabbitMqOptions { Exchange = "auth-tests" }),
            new FakeClock(new DateTimeOffset(Utc(1), TimeSpan.Zero)),
            logger);

        var publishedCount = await batchPublisher.PublishBatchAsync(CancellationToken.None);
        fixture.Context.ChangeTracker.Clear();

        var stored = await fixture.Context.OutboxMessages.SingleAsync();
        publishedCount.Should().Be(0);
        publisher.Messages.Should().BeEmpty();
        stored.PublishedAtUtc.Should().BeNull();
        stored.Attempts.Should().Be(1);
        stored.LockId.Should().BeNull();
        stored.LockedUntilUtc.Should().BeNull();
        stored.LastError.Should().NotBeNullOrWhiteSpace();
        stored.LastError.Should().NotContain(invalidProtectedPayload);
        logger.Entries.Should().OnlyContain(entry => !entry.Contains(invalidProtectedPayload, StringComparison.Ordinal));
    }

    [Fact]
    public async Task OutboxMessagePublisher_When_PublisherFails_Should_Not_Log_Or_Store_DecryptedPayload()
    {
        await using var fixture = await SqliteFixture.CreateAsync();
        var payloadProtector = CreatePayloadProtector();
        var logger = new CapturingLogger<OutboxMessagePublisher>();
        const string rawToken = "raw-reset-token-from-publisher-failure";
        var serializedPayload = JsonSerializer.Serialize(
            new AuthPasswordResetRequestedV1(Guid.NewGuid(), Guid.NewGuid(), "alice", "alice@example.com", rawToken, $"https://app.example.test/reset?token={rawToken}", Utc(30)),
            new JsonSerializerOptions(JsonSerializerDefaults.Web));
        fixture.Context.OutboxMessages.Add(new OutboxMessage
        {
            EventId = Guid.NewGuid(),
            EventName = AuthPasswordResetRequestedV1.EventName,
            EventVersion = AuthPasswordResetRequestedV1.EventVersion,
            Source = "Norge360.Auth",
            RoutingKey = AuthPasswordResetRequestedV1.RoutingKey,
            Payload = payloadProtector.ProtectForStorage(AuthPasswordResetRequestedV1.EventName, serializedPayload),
            OccurredAtUtc = Utc(0),
            CreatedAtUtc = Utc(0),
            NextAttemptAtUtc = Utc(0)
        });
        await fixture.Context.SaveChangesAsync();

        var batchPublisher = new OutboxMessagePublisher(
            fixture.Context,
            new ThrowingIntegrationEventPublisher(message => new InvalidOperationException($"downstream failed payload={message.Payload}")),
            payloadProtector,
            Options.Create(new OutboxOptions { BatchSize = 10, MaxAttempts = 3, LockSeconds = 30 }),
            Options.Create(new RabbitMqOptions { Exchange = "auth-tests" }),
            new FakeClock(new DateTimeOffset(Utc(1), TimeSpan.Zero)),
            logger);

        var publishedCount = await batchPublisher.PublishBatchAsync(CancellationToken.None);
        fixture.Context.ChangeTracker.Clear();

        var stored = await fixture.Context.OutboxMessages.SingleAsync();
        publishedCount.Should().Be(0);
        stored.PublishedAtUtc.Should().BeNull();
        stored.Attempts.Should().Be(1);
        stored.LastError.Should().NotBeNullOrWhiteSpace();
        stored.LastError.Should().NotContain(rawToken);
        stored.Payload.Should().StartWith(OutboxPayloadProtector.ProtectedPayloadPrefix);
        stored.Payload.Should().NotContain(rawToken);
        logger.Entries.Should().OnlyContain(entry => !entry.Contains(rawToken, StringComparison.Ordinal));
    }

    [Fact]
    public async Task OutboxMessagePublisher_When_LegacyPlaintextPayloadExists_Should_Publish_Without_Decryption()
    {
        await using var fixture = await SqliteFixture.CreateAsync();
        var payloadProtector = CreatePayloadProtector();
        var publisher = new CapturingIntegrationEventPublisher();
        const string legacyPayload = "{\"token\":\"legacy-raw-token\"}";
        fixture.Context.OutboxMessages.Add(new OutboxMessage
        {
            EventId = Guid.NewGuid(),
            EventName = AuthPasswordResetRequestedV1.EventName,
            EventVersion = AuthPasswordResetRequestedV1.EventVersion,
            Source = "Norge360.Auth",
            RoutingKey = AuthPasswordResetRequestedV1.RoutingKey,
            Payload = legacyPayload,
            OccurredAtUtc = Utc(0),
            CreatedAtUtc = Utc(0),
            NextAttemptAtUtc = Utc(0)
        });
        await fixture.Context.SaveChangesAsync();

        var batchPublisher = new OutboxMessagePublisher(
            fixture.Context,
            publisher,
            payloadProtector,
            Options.Create(new OutboxOptions { BatchSize = 10, MaxAttempts = 3, LockSeconds = 30 }),
            Options.Create(new RabbitMqOptions { Exchange = "auth-tests" }),
            new FakeClock(new DateTimeOffset(Utc(1), TimeSpan.Zero)),
            NullLogger<OutboxMessagePublisher>.Instance);

        var publishedCount = await batchPublisher.PublishBatchAsync(CancellationToken.None);

        publishedCount.Should().Be(1);
        publisher.Messages.Should().ContainSingle();
        publisher.Messages[0].Payload.Should().Be(legacyPayload);
    }

    [Fact]
    public void OutboxPayloadProtector_When_PayloadIsAlreadyProtected_Should_Not_DoubleProtect()
    {
        var payloadProtector = CreatePayloadProtector();
        var protectedPayload = OutboxPayloadProtector.ProtectedPayloadPrefix + "already-protected";

        var result = payloadProtector.ProtectForStorage(AuthPasswordResetRequestedV1.EventName, protectedPayload);

        result.Should().Be(protectedPayload);
    }

    [Fact]
    public async Task DataRetentionCleanupRunner_Should_Cleanup_PublishedOutbox_And_ExpiredLifecycleData()
    {
        await using var fixture = await SqliteFixture.CreateAsync();
        var tenantId = Guid.NewGuid();
        var user = AuthTestDataBuilder.User().WithTenant(tenantId).Build();
        var utcNow = Utc(100);

        fixture.Context.Tenants.Add(new Tenant { Id = tenantId, Name = "Tenant", Slug = "tenant", CreatedAt = utcNow });
        fixture.Context.Users.Add(user);
        fixture.Context.AuthVerificationTokens.AddRange(
            CreateVerificationToken(tenantId, user.Id, "old-token", utcNow.AddDays(-10)),
            CreateVerificationToken(tenantId, user.Id, "recent-token", utcNow.AddDays(-1)),
            CreateVerificationToken(tenantId, user.Id, "active-token", utcNow.AddDays(1)));
        fixture.Context.TenantInvitations.AddRange(
            AuthTestDataBuilder.Invitation(tenantId, user.Id, tokenHash: "old-invite", email: "old@example.com", expiresAtUtc: utcNow.AddDays(-40)),
            AuthTestDataBuilder.Invitation(tenantId, user.Id, tokenHash: "recent-invite", email: "recent@example.com", expiresAtUtc: utcNow.AddDays(-1)),
            AuthTestDataBuilder.Invitation(tenantId, user.Id, tokenHash: "active-invite", email: "active@example.com", expiresAtUtc: utcNow.AddDays(1)));
        fixture.Context.OutboxMessages.AddRange(
            CreateOutboxMessage("old-outbox", utcNow.AddDays(-10)),
            CreateOutboxMessage("recent-outbox", utcNow.AddDays(-1)),
            CreateUnpublishedOutboxMessage("old-unpublished-outbox", utcNow.AddDays(-10)));
        await fixture.Context.SaveChangesAsync();

        var runner = new DataRetentionCleanupRunner(
            fixture.Context,
            Options.Create(new DataRetentionOptions
            {
                ExpiredVerificationTokenRetentionDays = 7,
                ExpiredInvitationRetentionDays = 30,
                PublishedOutboxRetentionDays = 7
            }),
            new FakeClock(new DateTimeOffset(utcNow, TimeSpan.Zero)),
            NullLogger<DataRetentionCleanupRunner>.Instance);

        var result = await runner.RunOnceAsync(CancellationToken.None);
        fixture.Context.ChangeTracker.Clear();

        result.ExpiredVerificationTokenCount.Should().Be(1);
        result.ExpiredInvitationCount.Should().Be(1);
        result.PublishedOutboxCount.Should().Be(1);
        (await fixture.Context.OutboxMessages.CountAsync()).Should().Be(2);
        (await fixture.Context.AuthVerificationTokens.IgnoreQueryFilters().SingleAsync(x => x.TokenHash == "old-token")).IsDeleted.Should().BeTrue();
        (await fixture.Context.AuthVerificationTokens.IgnoreQueryFilters().SingleAsync(x => x.TokenHash == "recent-token")).IsDeleted.Should().BeFalse();
        (await fixture.Context.AuthVerificationTokens.IgnoreQueryFilters().SingleAsync(x => x.TokenHash == "active-token")).IsDeleted.Should().BeFalse();
        (await fixture.Context.TenantInvitations.IgnoreQueryFilters().SingleAsync(x => x.TokenHash == "old-invite")).IsDeleted.Should().BeTrue();
        (await fixture.Context.TenantInvitations.IgnoreQueryFilters().SingleAsync(x => x.TokenHash == "recent-invite")).IsDeleted.Should().BeFalse();
        (await fixture.Context.TenantInvitations.IgnoreQueryFilters().SingleAsync(x => x.TokenHash == "active-invite")).IsDeleted.Should().BeFalse();
        (await fixture.Context.OutboxMessages.SingleAsync(x => x.EventName == "old-unpublished-outbox")).PublishedAtUtc.Should().BeNull();
    }

    private static Task AddEventAsync<TEvent>(
        IntegrationEventOutbox outbox,
        string eventName,
        int eventVersion,
        string routingKey,
        TEvent payload) =>
        outbox.AddAsync(
            Guid.NewGuid(),
            eventName,
            eventVersion,
            routingKey,
            "Norge360.Auth",
            payload,
            "correlation",
            "trace",
            Utc(0),
            CancellationToken.None);

    private static OutboxPayloadProtector CreatePayloadProtector()
    {
        var keyDirectory = Directory.CreateDirectory(Path.Combine(Path.GetTempPath(), "Norge360-auth-outbox-tests", Guid.NewGuid().ToString("N")));
        var provider = DataProtectionProvider.Create(keyDirectory, builder => builder.SetApplicationName("Norge360.Auth.Tests"));
        return new OutboxPayloadProtector(provider);
    }

    private static AuthVerificationToken CreateVerificationToken(Guid tenantId, Guid userId, string tokenHash, DateTime expiresAtUtc) =>
        new()
        {
            TenantId = tenantId,
            UserId = userId,
            Purpose = AuthVerificationTokenPurpose.PasswordReset,
            TokenHash = tokenHash,
            ExpiresAtUtc = expiresAtUtc,
            CreatedAt = expiresAtUtc.AddMinutes(-30)
        };

    private static OutboxMessage CreateOutboxMessage(string eventName, DateTime publishedAtUtc) =>
        new()
        {
            EventId = Guid.NewGuid(),
            EventName = eventName,
            EventVersion = 1,
            Source = "Norge360.Auth",
            RoutingKey = $"{eventName}.v1",
            Payload = "{}",
            OccurredAtUtc = publishedAtUtc,
            CreatedAtUtc = publishedAtUtc,
            PublishedAtUtc = publishedAtUtc
        };

    private static OutboxMessage CreateUnpublishedOutboxMessage(string eventName, DateTime createdAtUtc) =>
        new()
        {
            EventId = Guid.NewGuid(),
            EventName = eventName,
            EventVersion = 1,
            Source = "Norge360.Auth",
            RoutingKey = $"{eventName}.v1",
            Payload = "{}",
            OccurredAtUtc = createdAtUtc,
            CreatedAtUtc = createdAtUtc,
            PublishedAtUtc = null,
            NextAttemptAtUtc = createdAtUtc
        };

    private static DateTime Utc(int minutes) => new DateTime(2026, 1, 1, 0, 0, 0, DateTimeKind.Utc).AddMinutes(minutes);

    private sealed class CapturingIntegrationEventPublisher : IIntegrationEventPublisher
    {
        public List<IntegrationMessage> Messages { get; } = [];

        public Task PublishAsync(string exchange, string routingKey, IntegrationMessage message, CancellationToken cancellationToken)
        {
            Messages.Add(message);
            return Task.CompletedTask;
        }
    }

    private sealed class ThrowingIntegrationEventPublisher(Func<IntegrationMessage, Exception> exceptionFactory) : IIntegrationEventPublisher
    {
        public Task PublishAsync(string exchange, string routingKey, IntegrationMessage message, CancellationToken cancellationToken)
            => Task.FromException(exceptionFactory(message));
    }

    private sealed class CapturingLogger<T> : ILogger<T>
    {
        public List<string> Entries { get; } = [];

        public IDisposable? BeginScope<TState>(TState state)
            where TState : notnull =>
            null;

        public bool IsEnabled(LogLevel logLevel) => true;

        public void Log<TState>(
            LogLevel logLevel,
            EventId eventId,
            TState state,
            Exception? exception,
            Func<TState, Exception?, string> formatter)
        {
            Entries.Add(formatter(state, exception));
            if (exception is not null)
            {
                Entries.Add(exception.ToString());
            }
        }
    }

    private sealed class SqliteFixture : IAsyncDisposable
    {
        private readonly SqliteConnection _connection;
        public AuthDbContext Context { get; }

        private SqliteFixture(SqliteConnection connection, AuthDbContext context)
        {
            _connection = connection;
            Context = context;
        }

        public static async Task<SqliteFixture> CreateAsync()
        {
            var connection = new SqliteConnection("Data Source=:memory:");
            await connection.OpenAsync();
            var options = new DbContextOptionsBuilder<AuthDbContext>().UseSqlite(connection).Options;
            var context = new AuthDbContext(options);
            await context.Database.EnsureCreatedAsync();
            return new SqliteFixture(connection, context);
        }

        public async ValueTask DisposeAsync()
        {
            await Context.DisposeAsync();
            await _connection.DisposeAsync();
        }
    }
}
