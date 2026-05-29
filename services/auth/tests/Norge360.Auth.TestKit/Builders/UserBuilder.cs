// <copyright file="UserBuilder.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using Norge360.Auth.Domain.Entities;

namespace Norge360.Auth.TestKit.Builders;

public sealed class UserBuilder
{
    private readonly User _user = new()
    {
        UserName = "jane.doe",
        NormalizedUserName = "JANE.DOE",
        Email = "jane.doe@example.com",
        NormalizedEmail = "JANE.DOE@EXAMPLE.COM",
        PasswordHash = "HASH",
        CreatedAt = new DateTime(2026, 1, 1, 0, 0, 0, DateTimeKind.Utc),
        Roles = "user",
        Permissions = "session:self,profile:self",
        IsLocked = false,
        IsDeleted = false
    };

    public UserBuilder WithId(Guid id)
    {
        typeof(Norge360.Entities.EntityBase)
            .GetProperty(nameof(Norge360.Entities.EntityBase.Id))!
            .SetValue(_user, id);
        return this;
    }

    public UserBuilder WithIdentity(string userName, string email)
    {
        _user.UserName = userName;
        _user.NormalizedUserName = userName.ToUpperInvariant();
        _user.Email = email;
        _user.NormalizedEmail = email.ToUpperInvariant();
        return this;
    }

    public UserBuilder WithPasswordHash(string hash)
    {
        _user.PasswordHash = hash;
        return this;
    }

    public UserBuilder WithMfaEnabled(DateTime enabledAtUtc)
    {
        _user.MfaEnabled = true;
        _user.MfaEnabledAt = enabledAtUtc;
        _user.AuthenticatorKeyProtected = "protected-authenticator-key";
        return this;
    }

    public UserBuilder AsLocked(DateTime lockoutEndAtUtc, int failedCount = 5)
    {
        _user.IsLocked = true;
        _user.LockoutEndAt = lockoutEndAtUtc;
        _user.AccessFailedCount = failedCount;
        return this;
    }

    public UserBuilder WithPlatformRoleDefaults()
    {
        _user.Roles = "user";
        _user.Permissions = "session:self,profile:self";
        return this;
    }

    public UserBuilder WithEmailConfirmed(DateTime? confirmedAtUtc = null)
    {
        _user.EmailConfirmed = true;
        _user.EmailConfirmedAt = confirmedAtUtc ?? new DateTime(2026, 1, 1, 0, 0, 0, DateTimeKind.Utc);
        return this;
    }

    public UserBuilder AsInactive()
    {
        _user.Deactivate();
        return this;
    }

    public User Build() => _user;
}
