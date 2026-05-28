using BenchmarkDotNet.Attributes;
using Microsoft.Extensions.Caching.Distributed;

namespace Norge360.Idempotency.DistributedCache.Benchmarks;

[MemoryDiagnoser]
public class Norge360IdempotencyDistributedCacheBenchmarks
{
    private readonly DistributedCacheIdempotencyStateStore _store;

    public Norge360IdempotencyDistributedCacheBenchmarks()
    {
        _store = new DistributedCacheIdempotencyStateStore(new InMemoryDistributedCache());
    }

    [Benchmark(Baseline = true)]
    public Task<bool> TryMarkInProgressAsync()
        => _store.TryMarkInProgressAsync("k1", "h1", TimeSpan.FromMinutes(5), CancellationToken.None);

    [Benchmark]
    public async Task<IdempotencyState?> MarkCompletedAndReadAsync()
    {
        await _store.MarkCompletedAsync("k2", "h2", "{}", TimeSpan.FromMinutes(5), CancellationToken.None);
        return await _store.GetAsync("k2", CancellationToken.None);
    }

    private sealed class InMemoryDistributedCache : IDistributedCache
    {
        private readonly Dictionary<string, byte[]> _store = new(StringComparer.Ordinal);

        public byte[]? Get(string key) => _store.TryGetValue(key, out var value) ? value : null;
        public Task<byte[]?> GetAsync(string key, CancellationToken token = default) => Task.FromResult(Get(key));
        public void Refresh(string key) { }
        public Task RefreshAsync(string key, CancellationToken token = default) => Task.CompletedTask;
        public void Remove(string key) => _store.Remove(key);
        public Task RemoveAsync(string key, CancellationToken token = default) { _store.Remove(key); return Task.CompletedTask; }
        public void Set(string key, byte[] value, DistributedCacheEntryOptions options) => _store[key] = value;
        public Task SetAsync(string key, byte[] value, DistributedCacheEntryOptions options, CancellationToken token = default) { _store[key] = value; return Task.CompletedTask; }
    }
}
