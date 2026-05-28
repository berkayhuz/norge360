using BenchmarkDotNet.Attributes;
using Moq;
using StackExchange.Redis;

namespace Norge360.Idempotency.Redis.Benchmarks;

[MemoryDiagnoser]
public class Norge360IdempotencyRedisBenchmarks
{
    private readonly RedisIdempotencyStateStore _store;

    public Norge360IdempotencyRedisBenchmarks()
    {
        var db = new Mock<IDatabase>(MockBehavior.Strict);

        db.Setup(x => x.StringSetAsync(
                It.IsAny<RedisKey>(),
                It.IsAny<RedisValue>(),
                It.IsAny<TimeSpan?>(),
                It.IsAny<When>()))
            .ReturnsAsync(true);

        db.Setup(x => x.StringSetAsync(
                It.IsAny<RedisKey>(),
                It.IsAny<RedisValue>(),
                It.IsAny<TimeSpan?>(),
                It.IsAny<When>(),
                It.IsAny<CommandFlags>()))
            .ReturnsAsync(true);

        db.Setup(x => x.StringGetAsync(It.IsAny<RedisKey>(), It.IsAny<CommandFlags>()))
            .ReturnsAsync((RedisValue)"{\"status\":1,\"requestHash\":\"h\",\"responseJson\":\"{}\"}");

        var mux = new Mock<IConnectionMultiplexer>(MockBehavior.Strict);
        mux.Setup(x => x.GetDatabase(It.IsAny<int>(), It.IsAny<object>())).Returns(db.Object);

        _store = new RedisIdempotencyStateStore(mux.Object);
    }

    [Benchmark(Baseline = true)]
    public Task<bool> TryMarkInProgressAsync()
        => _store.TryMarkInProgressAsync("k1", "h1", TimeSpan.FromMinutes(5), CancellationToken.None);

    [Benchmark]
    public Task<IdempotencyState?> GetAsync()
        => _store.GetAsync("k1", CancellationToken.None);
}
