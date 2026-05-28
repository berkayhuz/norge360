// <copyright file="AuthDbContextFactory.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Design;

namespace Norge360.Auth.Infrastructure.Persistence.DesignTime;

public sealed class AuthDbContextFactory : IDesignTimeDbContextFactory<AuthDbContext>
{
    public AuthDbContext CreateDbContext(string[] args)
    {
        var connectionString = Environment.GetEnvironmentVariable("Norge360_AUTH_MIGRATIONS_CONNECTION")
            ?? Environment.GetEnvironmentVariable("ConnectionStrings__IdentityConnection")
            ?? "Host=localhost;Port=5432;Database=CRM.AuthDb;Username=postgres;Password=postgres;SSL Mode=Require;Trust Server Certificate=true";

        var options = new DbContextOptionsBuilder<AuthDbContext>()
            .UseNpgsql(
                connectionString,
                npgsql => npgsql.MigrationsAssembly(typeof(AuthDbContext).Assembly.FullName))
            .Options;

        return new AuthDbContext(options);
    }
}
