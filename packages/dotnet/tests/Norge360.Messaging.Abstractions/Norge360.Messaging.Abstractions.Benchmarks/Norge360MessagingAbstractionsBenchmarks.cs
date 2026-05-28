// <copyright file="Norge360MessagingAbstractionsBenchmarks.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>
using BenchmarkDotNet.Attributes;
using Norge360.Messaging.Abstractions;

namespace Norge360.Messaging.Abstractions.Benchmarks;

[MemoryDiagnoser]
public class Norge360MessagingAbstractionsBenchmarks
{
    [Benchmark(Baseline = true)]
    public IntegrationEventMetadata CreateMetadata() =>
        new(Guid.NewGuid(), "OrderCreated", 1, "orders", DateTime.UtcNow, "corr", "trace");

    [Benchmark]
    public IntegrationMessage CreateMessage() =>
        new(new IntegrationEventMetadata(Guid.NewGuid(), "OrderCreated", 1, "orders", DateTime.UtcNow, "corr", "trace"), "{}");
}