// <copyright file="Norge360MediaBenchmarks.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>
using BenchmarkDotNet.Attributes;
using Microsoft.Extensions.Options;
using Norge360.Media.Options;
using Norge360.Media.Security;
using Norge360.Media.Urls;

namespace Norge360.Media.Benchmarks;

[MemoryDiagnoser]
public class Norge360MediaBenchmarks
{
    private readonly MediaUrlBuilder _urlBuilder = new(Microsoft.Extensions.Options.Options.Create(new MediaOptions { PublicBaseUrl = "https://cdn.Norge360.com" }));

    [Benchmark(Baseline = true)]
    public string BuildPublicUrl() => _urlBuilder.BuildPublicUrl("media/a/b.jpg");

    [Benchmark]
    public async Task<string> ComputeSha256Hex()
    {
        await using var stream = new MemoryStream([1,2,3,4,5,6,7,8,9]);
        return await MediaHashing.ComputeSha256HexAsync(stream, CancellationToken.None);
    }
}
