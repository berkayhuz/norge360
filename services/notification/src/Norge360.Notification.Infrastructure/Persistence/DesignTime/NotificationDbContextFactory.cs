// <copyright file="NotificationDbContextFactory.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Design;

namespace Norge360.Notification.Infrastructure.Persistence.DesignTime;

public sealed class NotificationDbContextFactory : IDesignTimeDbContextFactory<NotificationDbContext>
{
    public NotificationDbContext CreateDbContext(string[] args)
    {
        var connectionString = Environment.GetEnvironmentVariable("Norge360_NOTIFICATION_MIGRATIONS_CONNECTION")
            ?? Environment.GetEnvironmentVariable("ConnectionStrings__NotificationConnection")
            ?? "Host=localhost;Port=5432;Database=Norge360_Notification;Username=postgres;Password=postgres;SSL Mode=Require;Trust Server Certificate=true";

        var options = new DbContextOptionsBuilder<NotificationDbContext>()
            .UseNpgsql(
                connectionString,
                npgsql => npgsql.MigrationsAssembly(typeof(NotificationDbContext).Assembly.FullName))
            .Options;

        return new NotificationDbContext(options);
    }
}
