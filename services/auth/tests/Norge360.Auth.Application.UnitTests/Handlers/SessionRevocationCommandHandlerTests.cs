// <copyright file="SessionRevocationCommandHandlerTests.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using FluentAssertions;
using MediatR;
using Moq;
using Norge360.Auth.Application.Abstractions;
using Norge360.Auth.Application.Features.Commands;
using Norge360.Auth.Application.Features.Handlers;
using Norge360.Auth.TestKit.Fakes;

namespace Norge360.Auth.Application.UnitTests.Handlers;

public sealed class SessionRevocationCommandHandlerTests
{
    [Fact]
    public async Task RevokeSession_Should_Evict_Cache_When_Revoke_Succeeds()
    {
        var now = new DateTime(2026, 1, 10, 0, 0, 0, DateTimeKind.Utc);
        var clock = new FakeClock(now);
        var tenantId = Guid.NewGuid();
        var userId = Guid.NewGuid();
        var currentSessionId = Guid.NewGuid();
        var revokedSessionId = Guid.NewGuid();

        var sessionRepository = new Mock<IUserSessionRepository>();
        var sessionStateValidator = new Mock<IUserSessionStateValidator>();
        var auditTrail = new Mock<IAuthAuditTrail>();
        var unitOfWork = new Mock<IAuthUnitOfWork>();
        auditTrail.Setup(trail => trail.WriteAsync(It.IsAny<Norge360.Auth.Application.Records.AuthAuditRecord>(), It.IsAny<CancellationToken>()))
            .Returns(Task.CompletedTask);
        unitOfWork.Setup(work => work.SaveChangesAsync(It.IsAny<CancellationToken>())).ReturnsAsync(1);

        sessionRepository.Setup(repository => repository.RevokeAsync(
                tenantId,
                userId,
                revokedSessionId,
                now,
                It.IsAny<string>(),
                It.IsAny<CancellationToken>()))
            .ReturnsAsync(true);

        var sut = new RevokeSessionCommandHandler(
            sessionRepository.Object,
            sessionStateValidator.Object,
            auditTrail.Object,
            unitOfWork.Object,
            clock);

        var result = await sut.Handle(
            new RevokeSessionCommand(tenantId, userId, currentSessionId, revokedSessionId, null, null, null, null, null),
            CancellationToken.None);

        result.Should().BeTrue();
        sessionStateValidator.Verify(validator => validator.Evict(tenantId, revokedSessionId), Times.Once);
    }

    [Fact]
    public async Task RevokeSession_Should_Not_Evict_Cache_When_Revoke_Fails()
    {
        var now = new DateTime(2026, 1, 10, 0, 0, 0, DateTimeKind.Utc);
        var clock = new FakeClock(now);
        var tenantId = Guid.NewGuid();
        var userId = Guid.NewGuid();
        var currentSessionId = Guid.NewGuid();
        var revokedSessionId = Guid.NewGuid();

        var sessionRepository = new Mock<IUserSessionRepository>();
        var sessionStateValidator = new Mock<IUserSessionStateValidator>();
        var auditTrail = new Mock<IAuthAuditTrail>();
        var unitOfWork = new Mock<IAuthUnitOfWork>();

        sessionRepository.Setup(repository => repository.RevokeAsync(
                tenantId,
                userId,
                revokedSessionId,
                now,
                It.IsAny<string>(),
                It.IsAny<CancellationToken>()))
            .ReturnsAsync(false);

        var sut = new RevokeSessionCommandHandler(
            sessionRepository.Object,
            sessionStateValidator.Object,
            auditTrail.Object,
            unitOfWork.Object,
            clock);

        var result = await sut.Handle(
            new RevokeSessionCommand(tenantId, userId, currentSessionId, revokedSessionId, null, null, null, null, null),
            CancellationToken.None);

        result.Should().BeFalse();
        sessionStateValidator.Verify(validator => validator.Evict(It.IsAny<Guid>(), It.IsAny<Guid>()), Times.Never);
    }

    [Fact]
    public async Task RevokeOtherSessions_Should_Evict_Each_Revoked_Session()
    {
        var now = new DateTime(2026, 1, 10, 0, 0, 0, DateTimeKind.Utc);
        var clock = new FakeClock(now);
        var tenantId = Guid.NewGuid();
        var userId = Guid.NewGuid();
        var currentSessionId = Guid.NewGuid();
        var revokedA = Guid.NewGuid();
        var revokedB = Guid.NewGuid();

        var sessionRepository = new Mock<IUserSessionRepository>();
        var sessionStateValidator = new Mock<IUserSessionStateValidator>();
        var auditTrail = new Mock<IAuthAuditTrail>();
        var unitOfWork = new Mock<IAuthUnitOfWork>();
        auditTrail.Setup(trail => trail.WriteAsync(It.IsAny<Norge360.Auth.Application.Records.AuthAuditRecord>(), It.IsAny<CancellationToken>()))
            .Returns(Task.CompletedTask);
        unitOfWork.Setup(work => work.SaveChangesAsync(It.IsAny<CancellationToken>())).ReturnsAsync(1);

        sessionRepository.Setup(repository => repository.RevokeAllAsync(
                tenantId,
                userId,
                now,
                "user_revoked_other_sessions",
                currentSessionId,
                It.IsAny<CancellationToken>()))
            .ReturnsAsync([revokedA, revokedB]);

        var sut = new RevokeOtherSessionsCommandHandler(
            sessionRepository.Object,
            sessionStateValidator.Object,
            auditTrail.Object,
            unitOfWork.Object,
            clock);

        var result = await sut.Handle(
            new RevokeOtherSessionsCommand(tenantId, userId, currentSessionId, null, null, null, null, null),
            CancellationToken.None);

        result.Should().Be(Unit.Value);
        sessionStateValidator.Verify(validator => validator.Evict(tenantId, revokedA), Times.Once);
        sessionStateValidator.Verify(validator => validator.Evict(tenantId, revokedB), Times.Once);
    }
}
