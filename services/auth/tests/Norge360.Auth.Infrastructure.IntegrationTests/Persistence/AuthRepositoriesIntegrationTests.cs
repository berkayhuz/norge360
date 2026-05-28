// <copyright file="AuthRepositoriesIntegrationTests.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using FluentAssertions;
using Microsoft.Data.Sqlite;
using Microsoft.EntityFrameworkCore;
using Norge360.Auth.Domain.Entities;
using Norge360.Auth.Infrastructure.Persistence;
using Norge360.Auth.Infrastructure.Services;

namespace Norge360.Auth.Infrastructure.IntegrationTests.Persistence;

public sealed class AuthRepositoriesIntegrationTests
{
    [Fact]
    public async Task AuthVerificationTokenRepository_Should_Only_Return_Valid_Unconsumed_Token()
    {
        await using var fixture = await SqliteFixture.CreateAsync();
        var repository = new AuthVerificationTokenRepository(fixture.Context);
        var tenantId = Guid.NewGuid();
        var utcNow = Utc(10);
        var user = new User
        {
            TenantId = tenantId,
            UserName = "alice",
            NormalizedUserName = "ALICE",
            Email = "alice@example.com",
            NormalizedEmail = "ALICE@EXAMPLE.COM",
            PasswordHash = "hash",
            CreatedAt = utcNow
        };
        var userId = user.Id;

        fixture.Context.Tenants.Add(new Tenant { Id = tenantId, Name = "Tenant", Slug = "tenant", CreatedAt = utcNow });
        fixture.Context.Users.Add(user);

        fixture.Context.AuthVerificationTokens.AddRange(
            new AuthVerificationToken
            {
                TenantId = tenantId,
                UserId = userId,
                Purpose = AuthVerificationTokenPurpose.EmailConfirmation,
                TokenHash = "valid-hash",
                ExpiresAtUtc = utcNow.AddMinutes(30),
                CreatedAt = utcNow
            },
            new AuthVerificationToken
            {
                TenantId = tenantId,
                UserId = userId,
                Purpose = AuthVerificationTokenPurpose.EmailConfirmation,
                TokenHash = "expired-hash",
                ExpiresAtUtc = utcNow.AddMinutes(-1),
                CreatedAt = utcNow
            });
        await fixture.Context.SaveChangesAsync();

        var valid = await repository.GetValidAsync(tenantId, userId, AuthVerificationTokenPurpose.EmailConfirmation, "valid-hash", utcNow, CancellationToken.None);
        var expired = await repository.GetValidAsync(tenantId, userId, AuthVerificationTokenPurpose.EmailConfirmation, "expired-hash", utcNow, CancellationToken.None);

        valid.Should().NotBeNull();
        expired.Should().BeNull();
    }

    [Fact]
    public async Task UserMfaRecoveryCodeRepository_Consume_Should_Be_Single_Use()
    {
        await using var fixture = await SqliteFixture.CreateAsync();
        var repository = new UserMfaRecoveryCodeRepository(fixture.Context);
        var tenantId = Guid.NewGuid();
        var utcNow = Utc(20);
        var user = new User
        {
            TenantId = tenantId,
            UserName = "alice",
            NormalizedUserName = "ALICE",
            Email = "alice@example.com",
            NormalizedEmail = "ALICE@EXAMPLE.COM",
            PasswordHash = "hash",
            CreatedAt = utcNow
        };
        var userId = user.Id;

        fixture.Context.Tenants.Add(new Tenant { Id = tenantId, Name = "Tenant", Slug = "tenant", CreatedAt = utcNow });
        fixture.Context.Users.Add(user);

        fixture.Context.UserMfaRecoveryCodes.Add(new UserMfaRecoveryCode
        {
            TenantId = tenantId,
            UserId = userId,
            CodeHash = "code-hash",
            CreatedAt = utcNow
        });
        await fixture.Context.SaveChangesAsync();

        var first = await repository.ConsumeAsync(tenantId, userId, "code-hash", utcNow, CancellationToken.None);
        await fixture.Context.SaveChangesAsync();
        var second = await repository.ConsumeAsync(tenantId, userId, "code-hash", utcNow.AddMinutes(1), CancellationToken.None);

        first.Should().BeTrue();
        second.Should().BeFalse();
    }

    [Fact]
    public async Task UserSessionRepository_RevokeAll_Should_Revoke_Every_Active_Session_Except_Excluded()
    {
        await using var fixture = await SqliteFixture.CreateAsync();
        var repository = new UserSessionRepository(fixture.Context);
        var tenantId = Guid.NewGuid();
        var utcNow = Utc(0);
        var user = new User
        {
            TenantId = tenantId,
            UserName = "alice",
            NormalizedUserName = "ALICE",
            Email = "alice@example.com",
            NormalizedEmail = "ALICE@EXAMPLE.COM",
            PasswordHash = "hash",
            CreatedAt = utcNow
        };

        fixture.Context.Tenants.Add(new Tenant { Id = tenantId, Name = "Tenant", Slug = "tenant", CreatedAt = utcNow });
        fixture.Context.Users.Add(user);

        var keepSession = CreateSession(tenantId, user.Id);
        var rotateSession1 = CreateSession(tenantId, user.Id);
        var rotateSession2 = CreateSession(tenantId, user.Id);

        fixture.Context.UserSessions.AddRange(keepSession, rotateSession1, rotateSession2);
        await fixture.Context.SaveChangesAsync();

        var revokedIds = await repository.RevokeAllAsync(tenantId, user.Id, Utc(40), "security-event", keepSession.Id, CancellationToken.None);
        await fixture.Context.SaveChangesAsync();

        revokedIds.Should().HaveCount(2);
        var allSessions = await fixture.Context.UserSessions.AsNoTracking().ToArrayAsync();
        allSessions.Single(session => session.Id == keepSession.Id).IsRevoked.Should().BeFalse();
        allSessions.Where(session => session.Id != keepSession.Id).Should().OnlyContain(session => session.IsRevoked);
    }

    private static UserSession CreateSession(Guid tenantId, Guid userId) =>
        new()
        {
            TenantId = tenantId,
            UserId = userId,
            RefreshTokenFamilyId = Guid.NewGuid(),
            RefreshTokenHash = $"hash-{Guid.NewGuid():N}",
            RefreshTokenExpiresAt = Utc(300),
            CreatedAt = Utc(0)
        };

    private static DateTime Utc(int minutes) => new DateTime(2026, 1, 1, 0, 0, 0, DateTimeKind.Utc).AddMinutes(minutes);

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
