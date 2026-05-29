using Microsoft.EntityFrameworkCore;
using Norge360.Auth.Application.Abstractions;
using Norge360.Auth.Domain.Entities;

namespace Norge360.Auth.Infrastructure.Persistence;

public sealed class AuthDbContext(DbContextOptions<AuthDbContext> options) : DbContext(options), IAuthUnitOfWork
{
    public DbSet<User> Users => Set<User>();
    public DbSet<UserSession> UserSessions => Set<UserSession>();
    public DbSet<AuthVerificationToken> AuthVerificationTokens => Set<AuthVerificationToken>();
    public DbSet<OutboxMessage> OutboxMessages => Set<OutboxMessage>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<User>(builder =>
        {
            builder.ToTable("Users");
            builder.HasKey(x => x.Id);
            builder.Property(x => x.UserName).HasMaxLength(64).IsRequired();
            builder.Property(x => x.NormalizedUserName).HasMaxLength(64).IsRequired();
            builder.Property(x => x.Email).HasMaxLength(256).IsRequired();
            builder.Property(x => x.NormalizedEmail).HasMaxLength(256).IsRequired();
            builder.Property(x => x.PasswordHash).HasMaxLength(512).IsRequired();
            builder.Property(x => x.Roles).HasMaxLength(2048).IsRequired();
            builder.Property(x => x.Permissions).HasMaxLength(8192).IsRequired();
            builder.HasIndex(x => x.NormalizedEmail).IsUnique();
            builder.HasIndex(x => x.NormalizedUserName).IsUnique();
            builder.HasMany(x => x.Sessions).WithOne(x => x.User).HasForeignKey(x => x.UserId).OnDelete(DeleteBehavior.Restrict);
            builder.HasQueryFilter(x => !x.IsDeleted);
        });

        modelBuilder.Entity<UserSession>(builder =>
        {
            builder.ToTable("UserSessions");
            builder.HasKey(x => x.Id);
            builder.Property(x => x.RefreshTokenHash).HasMaxLength(256).IsRequired();
            builder.Property(x => x.UserAgent).HasMaxLength(512);
            builder.Property(x => x.IpAddress).HasMaxLength(64);
            builder.HasIndex(x => x.UserId);
            builder.HasIndex(x => x.RefreshTokenExpiresAt);
            builder.HasQueryFilter(x => !x.IsDeleted);
        });

        modelBuilder.Entity<AuthVerificationToken>(builder =>
        {
            builder.ToTable("AuthVerificationTokens");
            builder.HasKey(x => x.Id);
            builder.Property(x => x.Purpose).HasMaxLength(64).IsRequired();
            builder.Property(x => x.TokenHash).HasMaxLength(128).IsRequired();
            builder.HasIndex(x => new { x.UserId, x.Purpose, x.TokenHash }).IsUnique();
            builder.HasQueryFilter(x => !x.IsDeleted);
        });

        modelBuilder.Entity<OutboxMessage>(builder =>
        {
            builder.ToTable("OutboxMessages");
            builder.HasKey(x => x.Id);
            builder.Property(x => x.EventName).HasMaxLength(256).IsRequired();
            builder.Property(x => x.Source).HasMaxLength(128).IsRequired();
            builder.Property(x => x.RoutingKey).HasMaxLength(256).IsRequired();
            builder.Property(x => x.Payload).IsRequired();
        });
    }
}
