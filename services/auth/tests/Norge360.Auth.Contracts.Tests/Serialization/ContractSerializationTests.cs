// <copyright file="ContractSerializationTests.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using System.Text.Json;
using FluentAssertions;
using Microsoft.AspNetCore.Mvc;
using Norge360.Auth.Contracts.Requests;
using Norge360.Auth.Contracts.Responses;
using Norge360.Auth.TestKit.Builders;
using Norge360.Auth.TestKit.Helpers;

namespace Norge360.Auth.Contracts.Tests.Serialization;

public sealed class ContractSerializationTests
{
    [Fact]
    public void LoginRequest_Should_Serialize_Using_CamelCase_Property_Names()
    {
        var request = new LoginRequest(
            Guid.Parse("11111111-1111-1111-1111-111111111111"),
            "jane@example.com",
            "Password123!",
            false,
            "123456");

        var json = JsonSerializer.Serialize(request, JsonSerializationHelper.WebOptions);

        json.Should().Contain("\"tenantId\"");
        json.Should().Contain("\"emailOrUserName\"");
        json.Should().Contain("\"mfaCode\"");
    }

    [Fact]
    public void AuthenticationTokenResponse_Should_Roundtrip_Without_Shape_Loss()
    {
        var response = AuthTestDataBuilder.TokenResponse(
            tenantId: Guid.Parse("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"),
            userId: Guid.Parse("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"),
            sessionId: Guid.Parse("cccccccc-cccc-cccc-cccc-cccccccccccc"));

        var payload = JsonSerializer.Serialize(response, JsonSerializationHelper.WebOptions);
        var deserialized = JsonSerializer.Deserialize<AuthenticationTokenResponse>(payload, JsonSerializationHelper.WebOptions);

        deserialized.Should().NotBeNull();
        deserialized!.AccessToken.Should().Be(response.AccessToken);
        deserialized.SessionId.Should().Be(response.SessionId);
        deserialized.TenantId.Should().Be(response.TenantId);
        deserialized.UserId.Should().Be(response.UserId);
    }

    [Fact]
    public void ProblemDetails_Should_Preserve_Extension_Contract_For_Trace_And_Correlation()
    {
        var problem = new ProblemDetails
        {
            Status = 401,
            Title = "Second factor required",
            Detail = "Multi-factor authentication challenge is required for this account.",
            Type = "https://httpstatuses.com/401"
        };
        problem.Extensions["traceId"] = "trace-id";
        problem.Extensions["correlationId"] = "correlation-id";
        problem.Extensions["errorCode"] = "mfa_required";

        var payload = JsonSerializer.Serialize(problem, JsonSerializationHelper.WebOptions);

        payload.Should().Contain("\"traceId\"");
        payload.Should().Contain("\"correlationId\"");
        payload.Should().Contain("\"errorCode\":\"mfa_required\"");
    }
}
