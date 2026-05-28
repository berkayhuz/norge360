// <copyright file="TestClaimsPrincipalFactory.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;

namespace Norge360.Auth.TestKit.Factories;

public static class TestClaimsPrincipalFactory
{
    public static ClaimsPrincipal CreateAuthenticatedPrincipal(
        Guid tenantId,
        Guid userId,
        Guid sessionId,
        string email = "jane.doe@example.com",
        IEnumerable<string>? roles = null,
        IEnumerable<string>? permissions = null,
        string authenticationType = "TestAuth")
    {
        var claims = new List<Claim>
        {
            new("tenant_id", tenantId.ToString()),
            new(ClaimTypes.NameIdentifier, userId.ToString()),
            new(JwtRegisteredClaimNames.Sub, userId.ToString()),
            new(JwtRegisteredClaimNames.Sid, sessionId.ToString()),
            new(ClaimTypes.Email, email),
            new(JwtRegisteredClaimNames.Email, email)
        };

        claims.AddRange((roles ?? ["tenant-user"]).Select(role => new Claim(ClaimTypes.Role, role)));
        claims.AddRange((permissions ?? ["session:self"]).Select(permission => new Claim("permission", permission)));

        return new ClaimsPrincipal(new ClaimsIdentity(claims, authenticationType));
    }
}

