// <copyright file="TestDatabaseFixture.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using Microsoft.Data.Sqlite;
using Microsoft.EntityFrameworkCore;
using Norge360.Auth.Infrastructure.Persistence;

namespace Norge360.Auth.TestKit.Fixtures;

public sealed class TestDatabaseFixture : IAsyncDisposable
{
    private readonly SqliteConnection _connection = new("Data Source=:memory:;Cache=Shared");

    public async Task InitializeAsync()
    {
        await _connection.OpenAsync();
    }

    public AuthDbContext CreateDbContext()
    {
        var options = new DbContextOptionsBuilder<AuthDbContext>()
            .UseSqlite(_connection)
            .EnableDetailedErrors()
            .EnableSensitiveDataLogging()
            .Options;
        return new AuthDbContext(options);
    }

    public async Task ResetAsync()
    {
        await using var context = CreateDbContext();
        await context.Database.EnsureDeletedAsync();
        await context.Database.EnsureCreatedAsync();
    }

    public async ValueTask DisposeAsync()
    {
        await _connection.DisposeAsync();
    }
}

