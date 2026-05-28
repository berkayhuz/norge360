// <copyright file="TestConfiguration.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using Norge360.Auth.TestKit.Factories;

namespace Norge360.Auth.TestKit.Helpers;

public static class TestConfiguration
{
    public static Dictionary<string, string?> CreateAuthApiDefaults()
    {
        using var jwtFactory = new TestJwtFactory();
        return new Dictionary<string, string?>(StringComparer.OrdinalIgnoreCase)
        {
            ["ConnectionStrings:IdentityConnection"] = "Data Source=:memory:",
            ["Security:TrustedGateway:RequireTrustedGateway"] = "false",
            ["Security:Cors:AllowedOrigins:0"] = "https://localhost:7025",
            ["Security:Cors:AllowedOrigins:1"] = "https://localhost:5030",
            ["Security:Cors:AllowedOrigins:2"] = "http://localhost:7004",
            ["Security:TokenTransport:Mode"] = "CookiesOnly",
            ["Outbox:EnablePublisher"] = "false",
            ["DataRetention:EnableCleanupService"] = "false",
            ["Seed:AllowStartupSeed"] = "false",
            ["Database:ApplyMigrationsOnStartup"] = "false",
            ["Testing:SkipInfrastructureInitialization"] = "true",
            ["Infrastructure:DistributedCache:Provider"] = "Memory",
            ["Infrastructure:DistributedCache:RequireExternalProviderInProduction"] = "false",
            ["Jwt:Issuer"] = "https://localhost:7223",
            ["Jwt:Audience"] = "https://localhost:7025",
            ["Jwt:SigningKeys:0:KeyId"] = "auth-rsa-test-2026-01",
            ["Jwt:SigningKeys:0:IsCurrent"] = "true",
            ["Jwt:SigningKeys:0:PrivateKeyPem"] = jwtFactory.ExportPrivateKeyPem()
        };
    }
}
