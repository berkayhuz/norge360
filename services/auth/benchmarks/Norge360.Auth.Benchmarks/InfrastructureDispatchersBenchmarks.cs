// <copyright file="InfrastructureDispatchersBenchmarks.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using BenchmarkDotNet.Attributes;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;
using Norge360.Auth.Application.Abstractions;
using Norge360.Auth.Application.Options;
using Norge360.Auth.Application.Records;
using Norge360.Auth.Domain.Entities;
using Norge360.Auth.Infrastructure.Services;

namespace Norge360.Auth.Benchmarks;

[MemoryDiagnoser]
public class InfrastructureDispatchersBenchmarks
{
    private SecurityAlertPublisher _alertPublisherEnabled = default!;
    private SecurityAlertPublisher _alertPublisherDisabled = default!;
    private OutboxInviteNotificationDispatcher _outboxDispatcher = default!;
    private SecurityAlert _alert = default!;
    private Tenant _tenant = default!;
    private TenantInvitation _invitation = default!;
    private User _inviter = default!;

    [GlobalSetup]
    public void Setup()
    {
        _alertPublisherEnabled = new SecurityAlertPublisher(
            NullLogger<SecurityAlertPublisher>.Instance,
            Options.Create(new SecurityAlertOptions { EnableStructuredAlerts = true }));
        _alertPublisherDisabled = new SecurityAlertPublisher(
            NullLogger<SecurityAlertPublisher>.Instance,
            Options.Create(new SecurityAlertOptions { EnableStructuredAlerts = false }));

        _outboxDispatcher = new OutboxInviteNotificationDispatcher(
            new NoopIntegrationEventOutbox(),
            Options.Create(new InvitationDeliveryOptions
            {
                AcceptBaseUrl = "https://app.norge360.test",
                AcceptPath = "/invite/accept"
            }));

        _alert = new SecurityAlert(
            "auth.login.failed",
            "high",
            "password=Str0ng!Pass123; token=abc; Authorization=Bearer xyz",
            Guid.NewGuid(),
            Guid.NewGuid(),
            Guid.NewGuid(),
            "corr-id",
            "trace-id",
            "jwt=token-value");

        _tenant = new Tenant
        {
            Id = Guid.NewGuid(),
            Name = "Acme",
            Slug = "acme",
            CreatedAt = DateTime.UtcNow
        };

        _invitation = new TenantInvitation
        {
            TenantId = _tenant.Id,
            InvitedByUserId = Guid.NewGuid(),
            Email = "invitee@example.test",
            NormalizedEmail = "INVITEE@EXAMPLE.TEST",
            ExpiresAtUtc = DateTime.UtcNow.AddDays(7),
            TokenHash = "hash"
        };

        _inviter = new User
        {
            TenantId = _tenant.Id,
            UserName = "inviter",
            Email = "inviter@example.test",
            NormalizedEmail = "INVITER@EXAMPLE.TEST",
            NormalizedUserName = "INVITER",
            PasswordHash = "hash",
            Roles = "tenant-admin",
            Permissions = "customers.read"
        };
    }

    [Benchmark]
    public Task SecurityAlert_Publish_Enabled() => _alertPublisherEnabled.PublishAsync(_alert, CancellationToken.None);

    [Benchmark]
    public Task SecurityAlert_Publish_Disabled() => _alertPublisherDisabled.PublishAsync(_alert, CancellationToken.None);

    [Benchmark]
    public Task OutboxInvite_SendInviteCreated() => _outboxDispatcher.SendInviteCreatedAsync(
        _tenant,
        _invitation,
        _inviter,
        invitedUser: null,
        rawToken: "token",
        correlationId: "corr-id",
        traceId: "trace-id",
        utcNow: DateTime.UtcNow,
        CancellationToken.None);

    [Benchmark]
    public Task OutboxInvite_SendInviteResent() => _outboxDispatcher.SendInviteResentAsync(
        _tenant,
        _invitation,
        _inviter,
        invitedUser: null,
        rawToken: "token",
        correlationId: "corr-id",
        traceId: "trace-id",
        utcNow: DateTime.UtcNow,
        CancellationToken.None);

    private sealed class NoopIntegrationEventOutbox : IIntegrationEventOutbox
    {
        public Task AddAsync<TEvent>(
            Guid eventId,
            string eventName,
            int eventVersion,
            string routingKey,
            string source,
            TEvent payload,
            string? correlationId,
            string? traceId,
            DateTime occurredAtUtc,
            CancellationToken cancellationToken) => Task.CompletedTask;
    }
}

