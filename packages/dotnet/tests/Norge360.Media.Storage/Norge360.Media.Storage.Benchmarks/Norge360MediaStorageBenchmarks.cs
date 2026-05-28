// <copyright file="Norge360MediaStorageBenchmarks.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>
using BenchmarkDotNet.Attributes;
using Microsoft.Extensions.Options;
using Norge360.Media.Options;
using Norge360.Media.Storage;

namespace Norge360.Media.Storage.Benchmarks;

[MemoryDiagnoser]
public class Norge360MediaStorageBenchmarks
{
    private readonly string _rootPath = Path.Combine(Path.GetTempPath(), "norge360-media-bench");

    [Benchmark(Baseline = true)]
    public async Task SaveExistsDelete_LocalFile()
    {
        var provider = new LocalFileMediaStorageProvider(Microsoft.Extensions.Options.Options.Create(new MediaOptions { Local = new MediaLocalOptions { RootPath = _rootPath } }));
        var key = $"bench/{Guid.NewGuid():N}.bin";
        await using var payload = new MemoryStream([1,2,3,4,5]);

        await provider.SaveAsync(key, payload, "application/octet-stream", CancellationToken.None);
        _ = await provider.ExistsAsync(key, CancellationToken.None);
        await provider.DeleteAsync(key, CancellationToken.None);
    }
}
