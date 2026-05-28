// <copyright file="JwtAccessTokenFactoryBenchmarks.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using BenchmarkDotNet.Attributes;
using Microsoft.Extensions.Options;
using Microsoft.IdentityModel.Tokens;
using Norge360.Auth.Application.Abstractions;
using Norge360.Auth.Application.Options;
using Norge360.Auth.Domain.Entities;
using Norge360.Auth.Infrastructure.Services;
using Norge360.Clock;

namespace Norge360.Auth.Benchmarks;

[MemoryDiagnoser]
public class JwtAccessTokenFactoryBenchmarks
{
    private JwtAccessTokenFactory _factory = default!;
    private User _user = default!;
    private Guid _tenantId;
    private Guid _sessionId;

    [GlobalSetup]
    public void Setup()
    {
        _tenantId = Guid.NewGuid();
        _sessionId = Guid.NewGuid();
        _factory = new JwtAccessTokenFactory(
            Options.Create(new JwtOptions
            {
                Issuer = "https://auth.norge360.test",
                Audience = "api://norge360",
                AccessTokenMinutes = 15
            }),
            new FixedClock(DateTimeOffset.UtcNow),
            new StaticTokenSigningKeyProvider());

        _user = new User
        {
            UserName = "tester",
            Email = "tester@example.test",
            TokenVersion = 1,
            Roles = "tenant-user,tenant-admin",
            Permissions = "customers.read,customers.write,session:self"
        };
    }

    [Benchmark]
    public object Create_From_User() => _factory.Create(_user, _tenantId, _sessionId);

    [Benchmark]
    public object Create_From_Arguments() => _factory.Create(
        _user.Id,
        _user.UserName,
        _user.Email ?? string.Empty,
        _user.TokenVersion,
        _user.GetRoles(),
        _user.GetPermissions(),
        _tenantId,
        _sessionId);

    private sealed class FixedClock(DateTimeOffset now) : IClock
    {
        public DateTimeOffset UtcNow { get; } = now;
        public DateTime UtcDateTime { get; } = now.UtcDateTime;
    }

    private sealed class StaticTokenSigningKeyProvider : ITokenSigningKeyProvider
    {
        private readonly SigningCredentials _credentials;
        private readonly SecurityKey[] _keys;

        public StaticTokenSigningKeyProvider()
        {
            var rsa = System.Security.Cryptography.RSA.Create(2048);
            var key = new RsaSecurityKey(rsa) { KeyId = "bench-key" };
            _credentials = new SigningCredentials(key, SecurityAlgorithms.RsaSha256);
            _keys = [key];
        }

        public SigningCredentials GetCurrentSigningCredentials() => _credentials;
        public IReadOnlyCollection<SecurityKey> GetValidationKeys() => _keys;
        public string CurrentKeyId => "bench-key";
        public object GetJwksDocument(string issuer) => new { issuer, keys = Array.Empty<object>() };
    }
}
