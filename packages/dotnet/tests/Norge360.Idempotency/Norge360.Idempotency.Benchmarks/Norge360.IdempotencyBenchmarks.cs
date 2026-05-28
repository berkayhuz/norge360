using BenchmarkDotNet.Attributes;

namespace Norge360.Idempotency.Benchmarks;

[MemoryDiagnoser]
public class Norge360IdempotencyBenchmarks
{
    [Benchmark(Baseline = true)]
    public IdempotencyState CreateInProgressState()
        => IdempotencyState.InProgress("hash");

    [Benchmark]
    public IdempotencyState CreateCompletedState()
        => IdempotencyState.Completed("hash", "{\"ok\":true}");

    [Benchmark]
    public bool ReadCommandKey()
    {
        IIdempotentCommand command = new SampleCommand("abc");
        return !string.IsNullOrWhiteSpace(command.IdempotencyKey);
    }

    private sealed record SampleCommand(string? IdempotencyKey) : IIdempotentCommand;
}
