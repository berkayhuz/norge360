// <copyright file="RequestContextMiddlewareTests.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using FluentAssertions;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Logging.Abstractions;
using Norge360.Auth.API.Middlewares;

namespace Norge360.Auth.Api.FunctionalTests.Security;

public sealed class RequestContextMiddlewareTests
{
    [Fact]
    public async Task InvokeAsync_Should_Set_Correlation_Header_And_Continue_Pipeline()
    {
        var nextCalled = false;
        var sut = new RequestContextMiddleware(
            context =>
            {
                nextCalled = true;
                return Task.CompletedTask;
            },
            NullLogger<RequestContextMiddleware>.Instance);
        var httpContext = new DefaultHttpContext();

        await sut.InvokeAsync(httpContext);

        nextCalled.Should().BeTrue();
        httpContext.Response.Headers.ContainsKey("X-Correlation-Id").Should().BeTrue();
        httpContext.Response.Headers["X-Correlation-Id"].ToString().Should().NotBeNullOrWhiteSpace();
    }

    [Fact]
    public void GetOrCreateCorrelationId_Should_Return_NonEmpty_Value()
    {
        var context = new DefaultHttpContext();

        var correlationId = RequestContextMiddleware.GetOrCreateCorrelationId(context);

        correlationId.Should().NotBeNullOrWhiteSpace();
    }
}
