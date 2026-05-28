// <copyright file="AuthDbContext.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.ChangeTracking;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using Microsoft.EntityFrameworkCore.Storage.ValueConversion;
using Norge360.Auth.Application.Abstractions;
using Norge360.Auth.Domain.Entities;
using Norge360.Entities.Abstractions;

namespace Norge360.Auth.Infrastructure.Persistence;

public sealed class AuthDbContext(DbContextOptions<AuthDbContext> options) : DbContext(options), IAuthUnitOfWork
{
    public DbSet<Tenant> Tenants => Set<Tenant>();
    public DbSet<User> Users => Set<User>();
    public DbSet<UserTenantMembership> UserTenantMemberships => Set<UserTenantMembership>();
    public DbSet<UserSession> UserSessions => Set<UserSession>();
    public DbSet<AuthAuditEvent> AuthAuditEvents => Set<AuthAuditEvent>();
    public DbSet<OutboxMessage> OutboxMessages => Set<OutboxMessage>();
    public DbSet<AuthVerificationToken> AuthVerificationTokens => Set<AuthVerificationToken>();
    public DbSet<UserMfaRecoveryCode> UserMfaRecoveryCodes => Set<UserMfaRecoveryCode>();
    public DbSet<TrustedDevice> TrustedDevices => Set<TrustedDevice>();
    public DbSet<TenantInvitation> TenantInvitations => Set<TenantInvitation>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        var useDatabaseGeneratedRowVersion = string.Equals(Database.ProviderName, "Microsoft.EntityFrameworkCore.SqlServer", StringComparison.Ordinal);

        modelBuilder.Entity<Tenant>(ConfigureTenant);
        modelBuilder.Entity<User>(builder => ConfigureUser(builder, useDatabaseGeneratedRowVersion));
        modelBuilder.Entity<UserTenantMembership>(builder => ConfigureUserTenantMembership(builder, useDatabaseGeneratedRowVersion));
        modelBuilder.Entity<UserSession>(builder => ConfigureUserSession(builder, useDatabaseGeneratedRowVersion));
        modelBuilder.Entity<AuthAuditEvent>(builder => ConfigureAuthAuditEvent(builder, useDatabaseGeneratedRowVersion));
        modelBuilder.Entity<OutboxMessage>(builder => ConfigureOutboxMessage(builder, useDatabaseGeneratedRowVersion));
        modelBuilder.Entity<AuthVerificationToken>(builder => ConfigureAuthVerificationToken(builder, useDatabaseGeneratedRowVersion));
        modelBuilder.Entity<UserMfaRecoveryCode>(builder => ConfigureUserMfaRecoveryCode(builder, useDatabaseGeneratedRowVersion));
        modelBuilder.Entity<TrustedDevice>(builder => ConfigureTrustedDevice(builder, useDatabaseGeneratedRowVersion));
        modelBuilder.Entity<TenantInvitation>(builder => ConfigureTenantInvitation(builder, useDatabaseGeneratedRowVersion));

        ApplyUtcDateTimeConverters(modelBuilder);
        ApplySoftDeleteFilters(modelBuilder);
    }

    public override Task<int> SaveChangesAsync(CancellationToken cancellationToken = default)
    {
        ApplyAuditAndUtcNormalization();
        return base.SaveChangesAsync(cancellationToken);
    }

    private static void ConfigureTenant(EntityTypeBuilder<Tenant> builder)
    {
        builder.ToTable("Tenants");
        builder.HasKey(x => x.Id);
        builder.Property(x => x.Name).HasMaxLength(200).IsRequired();
        builder.Property(x => x.Slug).HasMaxLength(100).IsRequired();
        builder.Property(x => x.CreatedBy).HasMaxLength(64);
        builder.Property(x => x.UpdatedBy).HasMaxLength(64);
        builder.HasIndex(x => x.Slug).IsUnique();
        builder.HasMany(x => x.Users).WithOne().HasForeignKey(x => x.TenantId).OnDelete(DeleteBehavior.Restrict);
        builder.HasMany(x => x.Memberships).WithOne().HasForeignKey(x => x.TenantId).OnDelete(DeleteBehavior.Restrict);
        builder.HasMany(x => x.Sessions).WithOne().HasForeignKey(x => x.TenantId).OnDelete(DeleteBehavior.Restrict);
        builder.HasMany(x => x.AuditEvents).WithOne().HasForeignKey(x => x.TenantId).OnDelete(DeleteBehavior.Restrict);
        builder.HasMany(x => x.Invitations).WithOne().HasForeignKey(x => x.TenantId).OnDelete(DeleteBehavior.Restrict);
    }

    private static void ConfigureUser(EntityTypeBuilder<User> builder, bool useDatabaseGeneratedRowVersion)
    {
        builder.ToTable("Users");
        builder.HasKey(x => x.Id);
        builder.Property(x => x.UserName).HasMaxLength(64).IsRequired();
        builder.Property(x => x.NormalizedUserName).HasMaxLength(64).IsRequired();
        builder.Property(x => x.Email).HasMaxLength(256).IsRequired();
        builder.Property(x => x.NormalizedEmail).HasMaxLength(256).IsRequired();
        builder.Property(x => x.PasswordHash).HasMaxLength(512).IsRequired();
        builder.Property(x => x.FirstName).HasMaxLength(100);
        builder.Property(x => x.LastName).HasMaxLength(100);
        builder.Property(x => x.SecurityStamp).HasMaxLength(64).IsRequired();
        builder.Property(x => x.AuthenticatorKeyProtected).HasMaxLength(2048);
        builder.Property(x => x.Roles).HasMaxLength(2048).IsRequired();
        builder.Property(x => x.Permissions).HasMaxLength(8192).IsRequired();
        ConfigureRowVersion(builder.Property(x => x.RowVersion), useDatabaseGeneratedRowVersion);
        builder.HasIndex(x => x.NormalizedEmail).IsUnique();
        builder.HasIndex(x => new { x.TenantId, x.NormalizedUserName }).IsUnique();
        builder.HasIndex(x => new { x.TenantId, x.NormalizedEmail }).IsUnique();
        builder.HasMany(x => x.TenantMemberships).WithOne(x => x.User).HasForeignKey(x => x.UserId).OnDelete(DeleteBehavior.Restrict);
        builder.HasMany(x => x.Sessions).WithOne(x => x.User).HasForeignKey(x => x.UserId).OnDelete(DeleteBehavior.Restrict);
        builder.HasMany(x => x.AuditEvents).WithOne().HasForeignKey(x => x.UserId).OnDelete(DeleteBehavior.Restrict);
        builder.HasMany(x => x.VerificationTokens).WithOne().HasForeignKey(x => x.UserId).OnDelete(DeleteBehavior.Restrict);
        builder.HasMany(x => x.RecoveryCodes).WithOne(x => x.User).HasForeignKey(x => x.UserId).OnDelete(DeleteBehavior.Restrict);
        builder.HasMany(x => x.TrustedDevices).WithOne(x => x.User).HasForeignKey(x => x.UserId).OnDelete(DeleteBehavior.Restrict);
    }

    private static void ConfigureUserTenantMembership(EntityTypeBuilder<UserTenantMembership> builder, bool useDatabaseGeneratedRowVersion)
    {
        builder.ToTable("UserTenantMemberships");
        builder.HasKey(x => x.Id);
        builder.Property(x => x.Roles).HasMaxLength(2048).IsRequired();
        builder.Property(x => x.Permissions).HasMaxLength(8192).IsRequired();
        ConfigureRowVersion(builder.Property(x => x.RowVersion), useDatabaseGeneratedRowVersion);
        builder.HasIndex(x => new { x.TenantId, x.UserId }).IsUnique();
        builder.HasIndex(x => x.UserId);
    }

    private static void ConfigureUserSession(EntityTypeBuilder<UserSession> builder, bool useDatabaseGeneratedRowVersion)
    {
        builder.ToTable("UserSessions");
        builder.HasKey(x => x.Id);
        builder.Property(x => x.RefreshTokenFamilyId).IsRequired();
        builder.Property(x => x.RefreshTokenHash).HasMaxLength(256).IsRequired();
        builder.Property(x => x.IpAddress).HasMaxLength(64);
        builder.Property(x => x.UserAgent).HasMaxLength(512);
        builder.Property(x => x.RevokedReason).HasMaxLength(128);
        ConfigureRowVersion(builder.Property(x => x.RowVersion), useDatabaseGeneratedRowVersion);
        builder.HasIndex(x => new { x.TenantId, x.UserId });
        builder.HasIndex(x => new { x.TenantId, x.RefreshTokenExpiresAt });
        builder.HasIndex(x => new { x.TenantId, x.RefreshTokenFamilyId });
    }

    private static void ConfigureAuthAuditEvent(EntityTypeBuilder<AuthAuditEvent> builder, bool useDatabaseGeneratedRowVersion)
    {
        builder.ToTable("AuthAuditEvents");
        builder.HasKey(x => x.Id);
        builder.Property(x => x.EventType).HasMaxLength(128).IsRequired();
        builder.Property(x => x.Outcome).HasMaxLength(64).IsRequired();
        builder.Property(x => x.Identity).HasMaxLength(256);
        builder.Property(x => x.IpAddress).HasMaxLength(64);
        builder.Property(x => x.UserAgent).HasMaxLength(512);
        builder.Property(x => x.CorrelationId).HasMaxLength(128);
        builder.Property(x => x.TraceId).HasMaxLength(128);
        builder.Property(x => x.Metadata).HasMaxLength(4000);
        ConfigureRowVersion(builder.Property(x => x.RowVersion), useDatabaseGeneratedRowVersion);
        builder.HasIndex(x => new { x.TenantId, x.CreatedAt });
        builder.HasIndex(x => new { x.TenantId, x.EventType, x.CreatedAt });
    }

    private static void ConfigureOutboxMessage(EntityTypeBuilder<OutboxMessage> builder, bool useDatabaseGeneratedRowVersion)
    {
        builder.ToTable("OutboxMessages");
        builder.HasKey(x => x.Id);
        builder.Property(x => x.EventName).HasMaxLength(256).IsRequired();
        builder.Property(x => x.EventVersion).IsRequired();
        builder.Property(x => x.Source).HasMaxLength(128).IsRequired();
        builder.Property(x => x.RoutingKey).HasMaxLength(256).IsRequired();
        builder.Property(x => x.Payload).IsRequired();
        builder.Property(x => x.CorrelationId).HasMaxLength(128);
        builder.Property(x => x.TraceId).HasMaxLength(128);
        builder.Property(x => x.LastError);
        ConfigureRowVersion(builder.Property(x => x.RowVersion), useDatabaseGeneratedRowVersion);
        builder.HasIndex(x => x.EventId).IsUnique();
        builder.HasIndex(x => new { x.PublishedAtUtc, x.NextAttemptAtUtc, x.LockedUntilUtc });
        builder.HasIndex(x => new { x.EventName, x.EventVersion, x.OccurredAtUtc });
    }

    private static void ConfigureAuthVerificationToken(EntityTypeBuilder<AuthVerificationToken> builder, bool useDatabaseGeneratedRowVersion)
    {
        builder.ToTable("AuthVerificationTokens");
        builder.HasKey(x => x.Id);
        builder.Property(x => x.Purpose).HasMaxLength(64).IsRequired();
        builder.Property(x => x.TokenHash).HasMaxLength(128).IsRequired();
        builder.Property(x => x.Target).HasMaxLength(320);
        builder.Property(x => x.ConsumedByIpAddress).HasMaxLength(64);
        ConfigureRowVersion(builder.Property(x => x.RowVersion), useDatabaseGeneratedRowVersion);
        builder.HasIndex(x => new { x.TenantId, x.UserId, x.Purpose, x.TokenHash }).IsUnique();
        builder.HasIndex(x => new { x.TenantId, x.Purpose, x.ExpiresAtUtc });
    }

    private static void ConfigureUserMfaRecoveryCode(EntityTypeBuilder<UserMfaRecoveryCode> builder, bool useDatabaseGeneratedRowVersion)
    {
        builder.ToTable("UserMfaRecoveryCodes");
        builder.HasKey(x => x.Id);
        builder.Property(x => x.CodeHash).HasMaxLength(128).IsRequired();
        builder.Property(x => x.ConsumedByIpAddress).HasMaxLength(64);
        ConfigureRowVersion(builder.Property(x => x.RowVersion), useDatabaseGeneratedRowVersion);
        builder.HasIndex(x => new { x.TenantId, x.UserId, x.CodeHash }).IsUnique();
        builder.HasIndex(x => new { x.TenantId, x.UserId, x.ConsumedAtUtc });
    }

    private static void ConfigureTrustedDevice(EntityTypeBuilder<TrustedDevice> builder, bool useDatabaseGeneratedRowVersion)
    {
        builder.ToTable("TrustedDevices");
        builder.HasKey(x => x.Id);
        builder.Property(x => x.DeviceFingerprintHash).HasMaxLength(128).IsRequired();
        builder.Property(x => x.DeviceName).HasMaxLength(200);
        builder.Property(x => x.IpAddress).HasMaxLength(64);
        builder.Property(x => x.UserAgent).HasMaxLength(512);
        builder.Property(x => x.RevokedReason).HasMaxLength(128);
        ConfigureRowVersion(builder.Property(x => x.RowVersion), useDatabaseGeneratedRowVersion);
        builder.HasIndex(x => new { x.TenantId, x.UserId, x.DeviceFingerprintHash }).IsUnique();
        builder.HasIndex(x => new { x.TenantId, x.UserId, x.TrustedAtUtc });
    }

    private static void ConfigureTenantInvitation(EntityTypeBuilder<TenantInvitation> builder, bool useDatabaseGeneratedRowVersion)
    {
        builder.ToTable("TenantInvitations");
        builder.HasKey(x => x.Id);
        builder.Property(x => x.Email).HasMaxLength(256).IsRequired();
        builder.Property(x => x.NormalizedEmail).HasMaxLength(256).IsRequired();
        builder.Property(x => x.FirstName).HasMaxLength(100);
        builder.Property(x => x.LastName).HasMaxLength(100);
        builder.Property(x => x.TokenHash).HasMaxLength(128).IsRequired();
        builder.Property(x => x.LastDeliveryStatus).HasMaxLength(64);
        builder.Property(x => x.LastDeliveryErrorCode).HasMaxLength(128);
        builder.Property(x => x.LastDeliveryCorrelationId).HasMaxLength(128);
        builder.Property(x => x.Roles).HasMaxLength(2048).IsRequired();
        builder.Property(x => x.Permissions).HasMaxLength(8192).IsRequired();
        builder.Property(x => x.CreatedBy).HasMaxLength(64);
        builder.Property(x => x.UpdatedBy).HasMaxLength(64);
        ConfigureRowVersion(builder.Property(x => x.RowVersion), useDatabaseGeneratedRowVersion);
        builder.HasIndex(x => new { x.TenantId, x.TokenHash }).IsUnique();
        builder.HasIndex(x => new { x.TenantId, x.NormalizedEmail, x.AcceptedAtUtc });
        builder.HasIndex(x => new { x.TenantId, x.ExpiresAtUtc });
        builder.HasIndex(x => new { x.TenantId, x.RevokedAtUtc });
        builder.HasIndex(x => new { x.TenantId, x.LastSentAtUtc });
    }

    private static void ConfigureRowVersion(PropertyBuilder<byte[]> property, bool useDatabaseGeneratedRowVersion)
    {
        if (useDatabaseGeneratedRowVersion)
        {
            property.IsRowVersion();
            return;
        }

        property.IsConcurrencyToken();
    }

    private void ApplyAuditAndUtcNormalization()
    {
        var utcNow = DateTime.UtcNow;

        foreach (var entry in ChangeTracker.Entries())
        {
            NormalizeDateTimeProperties(entry);

            if (entry.Entity is not IAuditable auditableEntity)
            {
                continue;
            }

            if (entry.State == EntityState.Added)
            {
                if (auditableEntity.CreatedAt == default)
                {
                    auditableEntity.CreatedAt = utcNow;
                }

                auditableEntity.UpdatedAt = utcNow;
            }
            else if (entry.State == EntityState.Modified)
            {
                auditableEntity.UpdatedAt = utcNow;
            }
        }
    }

    private static void NormalizeDateTimeProperties(EntityEntry entry)
    {
        foreach (var property in entry.Properties)
        {
            if (property.Metadata.ClrType == typeof(DateTime) && property.CurrentValue is DateTime dateTime)
            {
                property.CurrentValue = NormalizeToUtc(dateTime);
            }
            else if (property.Metadata.ClrType == typeof(DateTime?) && property.CurrentValue is DateTime nullableDateTime)
            {
                property.CurrentValue = NormalizeToUtc(nullableDateTime);
            }
        }
    }

    private static DateTime NormalizeToUtc(DateTime value) =>
        value.Kind switch
        {
            DateTimeKind.Utc => value,
            DateTimeKind.Local => value.ToUniversalTime(),
            _ => DateTime.SpecifyKind(value, DateTimeKind.Utc)
        };

    private static void ApplyUtcDateTimeConverters(ModelBuilder modelBuilder)
    {
        var dateTimeConverter = new ValueConverter<DateTime, DateTime>(
            value => NormalizeToUtc(value),
            value => DateTime.SpecifyKind(value, DateTimeKind.Utc));
        var nullableDateTimeConverter = new ValueConverter<DateTime?, DateTime?>(
            value => value.HasValue ? NormalizeToUtc(value.Value) : value,
            value => value.HasValue ? DateTime.SpecifyKind(value.Value, DateTimeKind.Utc) : value);

        foreach (var entityType in modelBuilder.Model.GetEntityTypes())
        {
            foreach (var property in entityType.GetProperties())
            {
                if (property.ClrType == typeof(DateTime))
                {
                    property.SetValueConverter(dateTimeConverter);
                }
                else if (property.ClrType == typeof(DateTime?))
                {
                    property.SetValueConverter(nullableDateTimeConverter);
                }
            }
        }
    }

    private static void ApplySoftDeleteFilters(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<User>().HasQueryFilter(x => !x.IsDeleted);
        modelBuilder.Entity<UserTenantMembership>().HasQueryFilter(x => !x.IsDeleted);
        modelBuilder.Entity<UserSession>().HasQueryFilter(x => !x.IsDeleted);
        modelBuilder.Entity<AuthAuditEvent>().HasQueryFilter(x => !x.IsDeleted);
        modelBuilder.Entity<AuthVerificationToken>().HasQueryFilter(x => !x.IsDeleted);
        modelBuilder.Entity<UserMfaRecoveryCode>().HasQueryFilter(x => !x.IsDeleted);
        modelBuilder.Entity<TrustedDevice>().HasQueryFilter(x => !x.IsDeleted);
        modelBuilder.Entity<TenantInvitation>().HasQueryFilter(x => !x.IsDeleted);
    }
}
