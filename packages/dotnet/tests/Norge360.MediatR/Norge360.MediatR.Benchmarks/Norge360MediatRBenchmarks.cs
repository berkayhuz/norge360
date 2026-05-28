// <copyright file="Norge360MediatRBenchmarks.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>
using BenchmarkDotNet.Attributes;
using FluentValidation;
using Microsoft.Extensions.Logging.Abstractions;
using Norge360.MediatR;

namespace Norge360.MediatR.Benchmarks;

[MemoryDiagnoser]
public class Norge360MediatRBenchmarks
{
    [Benchmark(Baseline = true)]
    public Task<int> RequestLoggingBehavior_Handle()
    {
        var behavior = new RequestLoggingBehavior<DummyRequest, int>(NullLogger<RequestLoggingBehavior<DummyRequest, int>>.Instance);
        return behavior.Handle(new DummyRequest(), _ => Task.FromResult(42), CancellationToken.None);
    }

    [Benchmark]
    public Task<int> ValidationBehavior_NoValidators_Handle()
    {
        var behavior = new ValidationBehavior<DummyRequest, int>(Array.Empty<IValidator<DummyRequest>>());
        return behavior.Handle(new DummyRequest(), _ => Task.FromResult(42), CancellationToken.None);
    }

    private sealed record DummyRequest;
}
