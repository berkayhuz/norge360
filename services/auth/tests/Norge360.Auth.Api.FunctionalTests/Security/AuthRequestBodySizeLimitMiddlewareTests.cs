// <copyright file="AuthRequestBodySizeLimitMiddlewareTests.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using FluentAssertions;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Http.Features;
using Microsoft.Extensions.DependencyInjection;
using Norge360.Auth.API.Middlewares;
using Norge360.Auth.API.Security;

namespace Norge360.Auth.Api.FunctionalTests.Security;

public sealed class AuthRequestBodySizeLimitMiddlewareTests
{
    [Fact]
    public async Task InvokeAsync_Should_Bypass_When_Request_Is_Not_Auth_Post()
    {
        var nextCalled = false;
        var sut = new AuthRequestBodySizeLimitMiddleware(_ =>
        {
            nextCalled = true;
            return Task.CompletedTask;
        });
        var context = CreateContext("GET", "/api/auth/login");

        await sut.InvokeAsync(context);

        nextCalled.Should().BeTrue();
    }

    [Fact]
    public async Task InvokeAsync_Should_Set_MaxRequestBodySize_For_Auth_Post()
    {
        var sut = new AuthRequestBodySizeLimitMiddleware(_ => Task.CompletedTask);
        var context = CreateContext("POST", "/api/auth/login");
        var feature = new FakeMaxRequestBodySizeFeature { IsReadOnly = false };
        context.Features.Set<IHttpMaxRequestBodySizeFeature>(feature);

        await sut.InvokeAsync(context);

        feature.MaxRequestBodySize.Should().Be(AuthRequestSizeLimits.AuthBodyBytes);
    }

    [Fact]
    public async Task InvokeAsync_Should_Return_413_When_ContentLength_Exceeds_Limit()
    {
        var nextCalled = false;
        var sut = new AuthRequestBodySizeLimitMiddleware(_ =>
        {
            nextCalled = true;
            return Task.CompletedTask;
        });
        var context = CreateContext("POST", "/api/auth/login");
        context.Request.ContentLength = AuthRequestSizeLimits.AuthBodyBytes + 1;

        await sut.InvokeAsync(context);

        nextCalled.Should().BeFalse();
        context.Response.StatusCode.Should().Be(StatusCodes.Status413PayloadTooLarge);
    }

    [Fact]
    public async Task InvokeAsync_Should_Not_Set_MaxBodySize_When_Feature_Is_ReadOnly()
    {
        var sut = new AuthRequestBodySizeLimitMiddleware(_ => Task.CompletedTask);
        var context = CreateContext("POST", "/api/auth/register");
        var feature = new FakeMaxRequestBodySizeFeature { IsReadOnly = true };
        context.Features.Set<IHttpMaxRequestBodySizeFeature>(feature);

        await sut.InvokeAsync(context);

        feature.MaxRequestBodySize.Should().BeNull();
    }

    private static DefaultHttpContext CreateContext(string method, string path)
    {
        var context = new DefaultHttpContext();
        context.Request.Method = method;
        context.Request.Path = path;
        context.RequestServices = new ServiceCollection()
            .AddOptions()
            .AddProblemDetails()
            .BuildServiceProvider();
        return context;
    }

    private sealed class FakeMaxRequestBodySizeFeature : IHttpMaxRequestBodySizeFeature
    {
        public bool IsReadOnly { get; set; }
        public long? MaxRequestBodySize { get; set; }
    }
}
