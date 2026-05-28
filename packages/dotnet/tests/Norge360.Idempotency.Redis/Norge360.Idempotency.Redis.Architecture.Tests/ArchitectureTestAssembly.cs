using System.Reflection;

namespace Norge360.Idempotency.Redis.Architecture.Tests;

internal static class ArchitectureTestAssembly
{
    internal static readonly Assembly ProductionAssembly = typeof(Norge360.Idempotency.Redis.RedisIdempotencyStateStore).Assembly;
}
