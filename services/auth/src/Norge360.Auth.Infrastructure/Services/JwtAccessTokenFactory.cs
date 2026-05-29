// <copyright file="JwtAccessTokenFactory.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using Microsoft.Extensions.Options;
using Norge360.Auth.Application.Abstractions;
using Norge360.Auth.Application.Descriptors;
using Norge360.Auth.Application.Options;
using Norge360.Auth.Domain.Entities;
using Norge360.Clock;

namespace Norge360.Auth.Infrastructure.Services;

public sealed class JwtAccessTokenFactory(
    IOptions<JwtOptions> jwtOptions,
    IClock clock,
    ITokenSigningKeyProvider tokenSigningKeyProvider) : IAccessTokenFactory
{
    public AccessTokenDescriptor Create(User user, Guid sessionId)
        => Create(
            user.Id,
            user.UserName,
            user.Email ?? string.Empty,
            user.TokenVersion,
            user.GetRoles(),
            user.GetPermissions(),
            sessionId,
            authenticatedAt: null,
            authenticationMethods: null);

    public AccessTokenDescriptor Create(
        Guid userId,
        string userName,
        string email,
        int tokenVersion,
        IReadOnlyCollection<string> roles,
        IReadOnlyCollection<string> permissions,
        Guid sessionId,
        DateTimeOffset? authenticatedAt = null,
        IReadOnlyCollection<string>? authenticationMethods = null)
    {
        var utcNow = clock.UtcDateTime;
        var expiresAt = utcNow.AddMinutes(jwtOptions.Value.AccessTokenMinutes);
        var credentials = tokenSigningKeyProvider.GetCurrentSigningCredentials();
        var authAt = authenticatedAt ?? utcNow;
        var amr = authenticationMethods is { Count: > 0 }
            ? authenticationMethods
            : ["pwd"];

        var claims = new List<Claim>
        {
            new(JwtRegisteredClaimNames.Sub, userId.ToString()),
            new(JwtRegisteredClaimNames.UniqueName, userName),
            new(JwtRegisteredClaimNames.Email, email),
            new(JwtRegisteredClaimNames.Sid, sessionId.ToString()),
            new("token_version", tokenVersion.ToString()),
            new(JwtRegisteredClaimNames.Jti, Guid.NewGuid().ToString("N")),
            new(JwtRegisteredClaimNames.AuthTime, authAt.ToUnixTimeSeconds().ToString())
        };

        claims.AddRange(roles.Select(role => new Claim(ClaimTypes.Role, role)));
        claims.AddRange(permissions.Select(permission => new Claim("permission", permission)));
        claims.AddRange(amr.Select(method => new Claim("amr", method)));

        var token = new JwtSecurityToken(
            issuer: jwtOptions.Value.Issuer,
            audience: jwtOptions.Value.Audience,
            claims: claims,
            notBefore: utcNow,
            expires: expiresAt,
            signingCredentials: credentials);
        token.Header["kid"] = tokenSigningKeyProvider.CurrentKeyId;

        return new AccessTokenDescriptor(new JwtSecurityTokenHandler().WriteToken(token), expiresAt);
    }
}
