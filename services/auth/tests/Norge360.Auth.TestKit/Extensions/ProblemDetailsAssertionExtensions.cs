// <copyright file="ProblemDetailsAssertionExtensions.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using System.Text.Json.Nodes;
using FluentAssertions;

namespace Norge360.Auth.TestKit.Extensions;

public static class ProblemDetailsAssertionExtensions
{
    public static async Task<JsonNode> ShouldBeProblemDetailsAsync(
        this HttpResponseMessage response,
        int expectedStatusCode,
        string? expectedErrorCode = null)
    {
        response.StatusCode.Should().Be((System.Net.HttpStatusCode)expectedStatusCode);
        var payload = await response.Content.ReadAsStringAsync();
        var json = JsonNode.Parse(payload);
        json.Should().NotBeNull();
        json!["status"]!.GetValue<int>().Should().Be(expectedStatusCode);

        var traceId = json["extensions"]?["traceId"] ?? json["traceId"];
        var correlationId = json["extensions"]?["correlationId"] ?? json["correlationId"];
        traceId.Should().NotBeNull();
        correlationId.Should().NotBeNull();

        if (!string.IsNullOrWhiteSpace(expectedErrorCode))
        {
            var errorCode = json["extensions"]?["errorCode"] ?? json["errorCode"];
            errorCode.Should().NotBeNull();
            errorCode!.GetValue<string>().Should().Be(expectedErrorCode);
        }

        return json;
    }
}
