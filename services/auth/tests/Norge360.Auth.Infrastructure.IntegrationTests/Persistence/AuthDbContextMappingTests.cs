// <copyright file="AuthDbContextMappingTests.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using FluentAssertions;
using Microsoft.Data.Sqlite;
using Microsoft.EntityFrameworkCore;
using Norge360.Auth.Domain.Entities;
using Norge360.Auth.Infrastructure.Persistence;

namespace Norge360.Auth.Infrastructure.IntegrationTests.Persistence;

public sealed class AuthDbContextMappingTests
{
    [Fact]
    public async Task EnsureCreated_Should_Create_Auth_Tables()
    {
        await using var fixture = await SqliteFixture.CreateAsync();

        await using var command = fixture.Connection.CreateCommand();
        command.CommandText = "SELECT name FROM sqlite_master WHERE type='table'";
        var tableNames = new List<string>();
        await using var reader = await command.ExecuteReaderAsync();
        while (await reader.ReadAsync())
        {
            tableNames.Add(reader.GetString(0));
        }

        tableNames.Should().Contain(["Users", "UserSessions", "AuthVerificationTokens", "TenantInvitations"]);
    }

    [Fact]
    public async Task User_Unique_Index_Should_Reject_Duplicate_NormalizedEmail_Per_Tenant()
    {
        await using var fixture = await SqliteFixture.CreateAsync();
        var tenantId = Guid.NewGuid();
        fixture.Context.Tenants.Add(new Tenant { Id = tenantId, Name = "Tenant", Slug = "tenant", CreatedAt = Utc(0) });

        fixture.Context.Users.AddRange(
            CreateUser(tenantId, "alice", "ALICE", "alice@example.com", "ALICE@EXAMPLE.COM"),
            CreateUser(tenantId, "alice-2", "ALICE2", "alice.2@example.com", "ALICE@EXAMPLE.COM"));

        var act = async () => await fixture.Context.SaveChangesAsync();

        await act.Should().ThrowAsync<DbUpdateException>();
    }

    [Fact]
    public async Task User_Unique_Index_Should_Reject_Duplicate_NormalizedEmail_Across_Tenants()
    {
        await using var fixture = await SqliteFixture.CreateAsync();
        var firstTenantId = Guid.NewGuid();
        var secondTenantId = Guid.NewGuid();
        fixture.Context.Tenants.AddRange(
            new Tenant { Id = firstTenantId, Name = "Tenant 1", Slug = "tenant-1", CreatedAt = Utc(0) },
            new Tenant { Id = secondTenantId, Name = "Tenant 2", Slug = "tenant-2", CreatedAt = Utc(0) });

        fixture.Context.Users.AddRange(
            CreateUser(firstTenantId, "alice", "ALICE", "alice@example.com", "ALICE@EXAMPLE.COM"),
            CreateUser(secondTenantId, "alice-2", "ALICE2", "alice.2@example.com", "ALICE@EXAMPLE.COM"));

        var act = async () => await fixture.Context.SaveChangesAsync();

        await act.Should().ThrowAsync<DbUpdateException>();
    }

    [Fact]
    public async Task Query_Filter_Should_Exclude_Soft_Deleted_UserSessions()
    {
        await using var fixture = await SqliteFixture.CreateAsync();
        var tenantId = Guid.NewGuid();

        fixture.Context.Tenants.Add(new Tenant { Id = tenantId, Name = "Tenant", Slug = "tenant", CreatedAt = Utc(0) });
        var user = new User
        {
            TenantId = tenantId,
            UserName = "alice",
            NormalizedUserName = "ALICE",
            Email = "alice@example.com",
            NormalizedEmail = "ALICE@EXAMPLE.COM",
            PasswordHash = "hash",
            CreatedAt = Utc(0)
        };
        fixture.Context.Users.Add(user);
        fixture.Context.UserSessions.AddRange(
            new UserSession
            {
                TenantId = tenantId,
                UserId = user.Id,
                RefreshTokenFamilyId = Guid.NewGuid(),
                RefreshTokenHash = "token-1",
                RefreshTokenExpiresAt = Utc(60),
                CreatedAt = Utc(0),
                IsDeleted = false
            },
            new UserSession
            {
                TenantId = tenantId,
                UserId = user.Id,
                RefreshTokenFamilyId = Guid.NewGuid(),
                RefreshTokenHash = "token-2",
                RefreshTokenExpiresAt = Utc(60),
                CreatedAt = Utc(0),
                IsDeleted = true,
                DeletedAt = Utc(1)
            });
        await fixture.Context.SaveChangesAsync();

        var visibleCount = await fixture.Context.UserSessions.CountAsync();
        var totalCount = await fixture.Context.UserSessions.IgnoreQueryFilters().CountAsync();

        visibleCount.Should().Be(1);
        totalCount.Should().Be(2);
    }

    private static User CreateUser(Guid tenantId, string userName, string normalizedUserName, string email, string normalizedEmail) =>
        new()
        {
            TenantId = tenantId,
            UserName = userName,
            NormalizedUserName = normalizedUserName,
            Email = email,
            NormalizedEmail = normalizedEmail,
            PasswordHash = "hash",
            CreatedAt = Utc(0)
        };

    private static DateTime Utc(int minutes) => new DateTime(2026, 1, 1, 0, 0, 0, DateTimeKind.Utc).AddMinutes(minutes);

    private sealed class SqliteFixture : IAsyncDisposable
    {
        private readonly SqliteConnection _connection;
        public AuthDbContext Context { get; }
        public SqliteConnection Connection => _connection;

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
