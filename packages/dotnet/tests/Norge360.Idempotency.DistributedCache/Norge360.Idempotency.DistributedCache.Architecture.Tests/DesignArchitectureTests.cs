namespace Norge360.Idempotency.DistributedCache.Architecture.Tests;

public class DesignArchitectureTests
{
    [Fact]
    public void DistributedCacheIdempotencyStateStore_should_be_sealed()
    {
        Assert.True(typeof(DistributedCacheIdempotencyStateStore).IsSealed, "DistributedCacheIdempotencyStateStore should remain sealed.");
    }
}
