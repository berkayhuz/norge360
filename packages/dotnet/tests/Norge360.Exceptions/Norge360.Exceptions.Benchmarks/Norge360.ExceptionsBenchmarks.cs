// <copyright file="Norge360.ExceptionsBenchmarks.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using BenchmarkDotNet.Attributes;

namespace Norge360.Exceptions.Benchmarks;

[MemoryDiagnoser]
public class Norge360ExceptionsBenchmarks
{
    [Benchmark(Baseline = true)]
    public Exception CreateNotFoundException() => new NotFoundException("order", 42);

    [Benchmark]
    public Exception CreateValidationExceptionWithErrors()
        => new ValidationException("invalid", new Dictionary<string, string[]>
        {
            ["email"] = ["invalid format"]
        });

    [Benchmark]
    public string ReadForbiddenMessage() => new ForbiddenAccessException().Message;
}
