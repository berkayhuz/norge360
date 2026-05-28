// <copyright file="Norge360MessagingRabbitMqBenchmarks.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>
using BenchmarkDotNet.Attributes;
using Microsoft.Extensions.FileProviders;
using Microsoft.Extensions.Hosting;
using Norge360.Messaging.RabbitMq.Options;

namespace Norge360.Messaging.RabbitMq.Benchmarks;

[MemoryDiagnoser]
public class Norge360MessagingRabbitMqBenchmarks
{
    private readonly RabbitMqOptionsValidation _validation = new(new FakeHostEnvironment("Production"));

    [Benchmark(Baseline = true)]
    public bool ValidateProductionOptions()
    {
        var result = _validation.Validate(null, new RabbitMqOptions
        {
            Uri = "amqps://user:strong-password@broker.Norge360.com:5671",
            Exchange = "norge360.events"
        });

        return result.Succeeded;
    }

    private sealed class FakeHostEnvironment(string environmentName) : IHostEnvironment
    {
        public string EnvironmentName { get; set; } = environmentName;
        public string ApplicationName { get; set; } = "bench";
        public string ContentRootPath { get; set; } = AppContext.BaseDirectory;
        public IFileProvider ContentRootFileProvider { get; set; } = new NullFileProvider();
    }
}