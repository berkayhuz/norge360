// <copyright file="GlobalExceptionHandlerTests.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using FluentAssertions;
using FluentValidation;
using FluentValidation.Results;
using Microsoft.AspNetCore.Http;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging.Abstractions;
using Norge360.Auth.API.Exceptions;
using Norge360.Auth.Application.Exceptions;

namespace Norge360.Auth.Api.FunctionalTests.Security;

public sealed class GlobalExceptionHandlerTests
{
    [Fact]
    public async Task TryHandleAsync_Should_Return_Validation_ProblemDetails_For_ValidationException()
    {
        var writer = new CapturingProblemDetailsService();
        var sut = new GlobalExceptionHandler(NullLogger<GlobalExceptionHandler>.Instance);
        var context = CreateContext(writer);
        var exception = new ValidationException(
            [
                new ValidationFailure("email", "email is required"),
                new ValidationFailure("email", "email is invalid")
            ]);

        var handled = await sut.TryHandleAsync(context, exception, CancellationToken.None);

        handled.Should().BeTrue();
        context.Response.StatusCode.Should().Be(StatusCodes.Status400BadRequest);
        writer.LastProblemDetails.Should().NotBeNull();
        writer.LastProblemDetails!.Title.Should().Be("Validation failed");
    }

    [Fact]
    public async Task TryHandleAsync_Should_Map_AuthApplicationException()
    {
        var writer = new CapturingProblemDetailsService();
        var sut = new GlobalExceptionHandler(NullLogger<GlobalExceptionHandler>.Instance);
        var context = CreateContext(writer);
        var exception = new AuthApplicationException(
            "Forbidden",
            "not allowed",
            StatusCodes.Status403Forbidden,
            errorCode: "forbidden_operation");

        var handled = await sut.TryHandleAsync(context, exception, CancellationToken.None);

        handled.Should().BeTrue();
        context.Response.StatusCode.Should().Be(StatusCodes.Status403Forbidden);
        writer.LastProblemDetails.Should().NotBeNull();
        writer.LastProblemDetails!.Title.Should().Be("Forbidden");
        writer.LastProblemDetails.Extensions["errorCode"].Should().Be("forbidden_operation");
    }

    [Fact]
    public async Task TryHandleAsync_Should_Map_DbUpdateConcurrencyException_To_409()
    {
        var writer = new CapturingProblemDetailsService();
        var sut = new GlobalExceptionHandler(NullLogger<GlobalExceptionHandler>.Instance);
        var context = CreateContext(writer);

        var handled = await sut.TryHandleAsync(context, new DbUpdateConcurrencyException("conflict"), CancellationToken.None);

        handled.Should().BeTrue();
        context.Response.StatusCode.Should().Be(StatusCodes.Status409Conflict);
        writer.LastProblemDetails.Should().NotBeNull();
        writer.LastProblemDetails!.Extensions["errorCode"].Should().Be("concurrency_conflict");
    }

    [Fact]
    public async Task TryHandleAsync_Should_Map_Unknown_Exception_To_500()
    {
        var writer = new CapturingProblemDetailsService();
        var sut = new GlobalExceptionHandler(NullLogger<GlobalExceptionHandler>.Instance);
        var context = CreateContext(writer);

        var handled = await sut.TryHandleAsync(context, new InvalidOperationException("boom"), CancellationToken.None);

        handled.Should().BeTrue();
        context.Response.StatusCode.Should().Be(StatusCodes.Status500InternalServerError);
        writer.LastProblemDetails.Should().NotBeNull();
        writer.LastProblemDetails!.Extensions["errorCode"].Should().Be("server_error");
    }

    private static DefaultHttpContext CreateContext(CapturingProblemDetailsService writer)
    {
        var context = new DefaultHttpContext();
        context.Request.Path = "/api/auth/test";
        context.RequestServices = new ServiceCollection()
            .AddSingleton<IProblemDetailsService>(writer)
            .BuildServiceProvider();
        return context;
    }

    private sealed class CapturingProblemDetailsService : IProblemDetailsService
    {
        public Microsoft.AspNetCore.Mvc.ProblemDetails? LastProblemDetails { get; private set; }

        public ValueTask<bool> TryWriteAsync(ProblemDetailsContext context)
        {
            LastProblemDetails = context.ProblemDetails;
            return ValueTask.FromResult(true);
        }

        public ValueTask WriteAsync(ProblemDetailsContext context)
        {
            LastProblemDetails = context.ProblemDetails;
            return ValueTask.CompletedTask;
        }
    }
}
