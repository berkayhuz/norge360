// <copyright file="AuthTestDataBuilder.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using Norge360.Auth.Application.Descriptors;
using Norge360.Auth.Contracts.Responses;
using Norge360.Auth.Domain.Entities;

namespace Norge360.Auth.TestKit.Builders;

public static class AuthTestDataBuilder
{
    public static UserBuilder User() => new();

    public static LoginRequestBuilder LoginRequest() => new();

    public static RegisterRequestBuilder RegisterRequest() => new();

    public static AuthenticationTokenResponse TokenResponse(
        Guid? userId = null,
        Guid? sessionId = null)
    {
        var now = new DateTime(2026, 1, 1, 0, 0, 0, DateTimeKind.Utc);
        return new AuthenticationTokenResponse(
            "test-only-placeholder",
            now.AddMinutes(15),
            "test-only-placeholder",
            now.AddDays(14),
            userId ?? Guid.NewGuid(),
            "jane.doe",
            "jane.doe@example.com",
            sessionId ?? Guid.NewGuid());
    }

    private const string DescriptorPlaceholderValue = "example-value-for-tests";

    public static AccessTokenDescriptor AccessTokenDescriptor(string? value = null) =>
        new(
            value ?? DescriptorPlaceholderValue,
            new DateTime(2026, 1, 1, 0, 15, 0, DateTimeKind.Utc));

    public static RefreshTokenDescriptor RefreshTokenDescriptor(string? value = null, string? digest = null) =>
        new(
            value ?? DescriptorPlaceholderValue,
            digest ?? DescriptorPlaceholderValue,
            new DateTime(2026, 1, 15, 0, 0, 0, DateTimeKind.Utc));
}
