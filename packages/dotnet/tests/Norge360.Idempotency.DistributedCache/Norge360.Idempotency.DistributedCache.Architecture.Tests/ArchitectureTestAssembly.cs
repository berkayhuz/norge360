using System.Reflection;

namespace Norge360.Idempotency.DistributedCache.Architecture.Tests;

internal static class ArchitectureTestAssembly
{
    internal static readonly Assembly ProductionAssembly = typeof(Norge360.Idempotency.DistributedCache.DistributedCacheIdempotencyStateStore).Assembly;
}
