// <copyright file="NotificationDbContext.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using Microsoft.EntityFrameworkCore;
using Norge360.Notification.Domain.Entities;

namespace Norge360.Notification.Infrastructure.Persistence;

public sealed class NotificationDbContext(DbContextOptions<NotificationDbContext> options) : DbContext(options)
{
    public DbSet<NotificationMessage> Notifications => Set<NotificationMessage>();
    public DbSet<NotificationDeliveryAttempt> DeliveryAttempts => Set<NotificationDeliveryAttempt>();
    public DbSet<InAppNotificationRecord> InAppNotifications => Set<InAppNotificationRecord>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<NotificationMessage>(builder =>
        {
            builder.ToTable("Notifications");
            builder.HasKey(x => x.Id);
            builder.Property(x => x.Subject).HasMaxLength(512).IsRequired();
            builder.Property(x => x.TextBody).HasMaxLength(8000).IsRequired();
            builder.Property(x => x.HtmlBody).HasMaxLength(16000);
            builder.Property(x => x.TemplateKey).HasMaxLength(256);
            builder.Property(x => x.ChannelsJson).HasMaxLength(512).IsRequired();
            builder.Property(x => x.RecipientEmailAddress).HasMaxLength(320);
            builder.Property(x => x.RecipientPhoneNumber).HasMaxLength(64);
            builder.Property(x => x.RecipientPushToken).HasMaxLength(1024);
            builder.Property(x => x.RecipientDisplayName).HasMaxLength(256);
            builder.Property(x => x.MetadataJson).HasMaxLength(8000).IsRequired();
            builder.Property(x => x.CorrelationId).HasMaxLength(128);
            builder.Property(x => x.IdempotencyKey).HasMaxLength(256);
            builder.HasIndex(x => x.IdempotencyKey).IsUnique().HasFilter("\"IdempotencyKey\" IS NOT NULL");
            builder.HasMany(x => x.DeliveryAttempts)
                .WithOne(x => x.NotificationMessage)
                .HasForeignKey(x => x.NotificationMessageId)
                .OnDelete(DeleteBehavior.Cascade);
        });

        modelBuilder.Entity<NotificationDeliveryAttempt>(builder =>
        {
            builder.ToTable("NotificationDeliveryAttempts");
            builder.HasKey(x => x.Id);
            builder.Property(x => x.Provider).HasMaxLength(128).IsRequired();
            builder.Property(x => x.Recipient).HasMaxLength(512);
            builder.Property(x => x.ExternalMessageId).HasMaxLength(256);
            builder.Property(x => x.ErrorCode).HasMaxLength(128);
            builder.Property(x => x.ErrorMessage).HasMaxLength(2000);
            builder.HasIndex(x => new { x.NotificationMessageId, x.Channel });
        });

        modelBuilder.Entity<InAppNotificationRecord>(builder =>
        {
            builder.ToTable("InAppNotifications");
            builder.HasKey(x => x.Id);
            builder.Property(x => x.Subject).HasMaxLength(512).IsRequired();
            builder.Property(x => x.Body).HasMaxLength(8000).IsRequired();
            builder.Property(x => x.CorrelationId).HasMaxLength(128);
            builder.HasIndex(x => new { x.UserId, x.CreatedAtUtc });
        });
    }
}
