namespace Norge360.Idempotency.Redis.Architecture.Tests;

public class DesignArchitectureTests
{
    [Fact]
    public void RedisIdempotencyStateStore_should_be_sealed()
    {
        Assert.True(typeof(RedisIdempotencyStateStore).IsSealed, "RedisIdempotencyStateStore should remain sealed.");
    }
}
