// <copyright file="LogoutCommandHandlerTests.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using FluentAssertions;
using Microsoft.AspNetCore.Http;
using Moq;
using Norge360.Auth.Application.Abstractions;
using Norge360.Auth.Application.Exceptions;
using Norge360.Auth.Application.Features.Commands;
using Norge360.Auth.Application.Features.Handlers;
using Norge360.Auth.Domain.Entities;
using Norge360.Auth.TestKit.Fakes;

namespace Norge360.Auth.Application.UnitTests.Handlers;

public sealed class LogoutCommandHandlerTests
{
    [Fact]
    public async Task Handle_When_RefreshToken_Is_Valid_Should_Revoke_Session_And_Evict_SessionState()
    {
        var now = new DateTime(2026, 1, 9, 0, 0, 0, DateTimeKind.Utc);
        var tenantId = Guid.NewGuid();
        var session = new UserSession
        {
            TenantId = tenantId,
            UserId = Guid.NewGuid(),
            RefreshTokenHash = "refresh-token-hash",
            RefreshTokenExpiresAt = now.AddDays(14),
            IpAddress = "127.0.0.1",
            UserAgent = "unit-test"
        };
        var fixture = new Fixture(new FakeClock(now));
        fixture.SessionRepository.Setup(repository => repository.GetAsync(tenantId, session.Id, It.IsAny<CancellationToken>()))
            .ReturnsAsync(session);
        fixture.RefreshTokenService.Setup(service => service.Verify("refresh-token", "refresh-token-hash"))
            .Returns(true);

        var sut = fixture.CreateSut();

        await sut.Handle(new LogoutCommand(tenantId, session.Id, "refresh-token"), CancellationToken.None);

        session.IsRevoked.Should().BeTrue();
        session.RevokedReason.Should().Be("logout");
        fixture.UnitOfWork.Verify(unitOfWork => unitOfWork.SaveChangesAsync(It.IsAny<CancellationToken>()), Times.Once);
        fixture.SessionStateValidator.Verify(validator => validator.Evict(tenantId, session.Id), Times.Once);
    }

    [Fact]
    public async Task Handle_When_Session_Is_Already_Revoked_Should_Evict_State_Without_Rewriting()
    {
        var now = new DateTime(2026, 1, 9, 0, 0, 0, DateTimeKind.Utc);
        var tenantId = Guid.NewGuid();
        var session = new UserSession
        {
            TenantId = tenantId,
            UserId = Guid.NewGuid(),
            RefreshTokenHash = "refresh-token-hash",
            RefreshTokenExpiresAt = now.AddDays(14)
        };
        session.Revoke(now.AddMinutes(-5), "logout");
        var fixture = new Fixture(new FakeClock(now));
        fixture.SessionRepository.Setup(repository => repository.GetAsync(tenantId, session.Id, It.IsAny<CancellationToken>()))
            .ReturnsAsync(session);

        var sut = fixture.CreateSut();

        await sut.Handle(new LogoutCommand(tenantId, session.Id, "refresh-token"), CancellationToken.None);

        fixture.UnitOfWork.Verify(unitOfWork => unitOfWork.SaveChangesAsync(It.IsAny<CancellationToken>()), Times.Never);
        fixture.SessionStateValidator.Verify(validator => validator.Evict(tenantId, session.Id), Times.Once);
    }

    [Fact]
    public async Task Handle_When_RefreshToken_Is_Invalid_Should_Not_Revoke_Session()
    {
        var now = new DateTime(2026, 1, 9, 0, 0, 0, DateTimeKind.Utc);
        var tenantId = Guid.NewGuid();
        var session = new UserSession
        {
            TenantId = tenantId,
            UserId = Guid.NewGuid(),
            RefreshTokenHash = "refresh-token-hash",
            RefreshTokenExpiresAt = now.AddDays(14)
        };
        var fixture = new Fixture(new FakeClock(now));
        fixture.SessionRepository.Setup(repository => repository.GetAsync(tenantId, session.Id, It.IsAny<CancellationToken>()))
            .ReturnsAsync(session);
        fixture.RefreshTokenService.Setup(service => service.Verify("wrong-refresh-token", "refresh-token-hash"))
            .Returns(false);

        var sut = fixture.CreateSut();

        var action = async () => await sut.Handle(new LogoutCommand(tenantId, session.Id, "wrong-refresh-token"), CancellationToken.None);

        var exception = await action.Should().ThrowAsync<AuthApplicationException>();
        exception.Which.ErrorCode.Should().Be("invalid_refresh_token");
        session.IsRevoked.Should().BeFalse();
        fixture.UnitOfWork.Verify(unitOfWork => unitOfWork.SaveChangesAsync(It.IsAny<CancellationToken>()), Times.Never);
        fixture.SessionStateValidator.Verify(validator => validator.Evict(It.IsAny<Guid>(), It.IsAny<Guid>()), Times.Never);
    }

    private sealed class Fixture
    {
        private readonly FakeClock _clock;

        public Mock<IUserSessionRepository> SessionRepository { get; } = new();
        public Mock<IAuthUnitOfWork> UnitOfWork { get; } = new();
        public Mock<IAuthAuditTrail> AuditTrail { get; } = new();
        public Mock<IRefreshTokenService> RefreshTokenService { get; } = new();
        public Mock<IUserSessionStateValidator> SessionStateValidator { get; } = new();
        public Mock<IHttpContextAccessor> HttpContextAccessor { get; } = new();

        public Fixture(FakeClock clock)
        {
            _clock = clock;
            AuditTrail.Setup(trail => trail.WriteAsync(It.IsAny<Norge360.Auth.Application.Records.AuthAuditRecord>(), It.IsAny<CancellationToken>()))
                .Returns(Task.CompletedTask);
            UnitOfWork.Setup(unitOfWork => unitOfWork.SaveChangesAsync(It.IsAny<CancellationToken>()))
                .ReturnsAsync(1);
            HttpContextAccessor.Setup(accessor => accessor.HttpContext).Returns(new DefaultHttpContext());
        }

        public LogoutCommandHandler CreateSut() =>
            new(
                SessionRepository.Object,
                UnitOfWork.Object,
                AuditTrail.Object,
                RefreshTokenService.Object,
                SessionStateValidator.Object,
                _clock,
                HttpContextAccessor.Object);
    }
}
