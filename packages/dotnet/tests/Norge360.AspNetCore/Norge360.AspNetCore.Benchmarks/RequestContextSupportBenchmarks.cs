// <copyright file="RequestContextSupportBenchmarks.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using BenchmarkDotNet.Attributes;
using Microsoft.AspNetCore.Http;
using Norge360.AspNetCore.RequestContext;

namespace Norge360.AspNetCore.Benchmarks;

[MemoryDiagnoser]
public class RequestContextSupportBenchmarks
{
    private DefaultHttpContext _emptyContext = null!;
    private DefaultHttpContext _headerContext = null!;

    [GlobalSetup]
    public void Setup()
    {
        _emptyContext = new DefaultHttpContext();

        _headerContext = new DefaultHttpContext();
        _headerContext.Request.Headers[RequestContextSupport.CorrelationIdHeaderName] = "req-12345-abcdef";
    }

    [Benchmark]
    public string GetOrCreateCorrelationId_EmptyContext() =>
        RequestContextSupport.GetOrCreateCorrelationId(_emptyContext);

    [Benchmark]
    public string GetOrCreateCorrelationId_FromHeader() =>
        RequestContextSupport.GetOrCreateCorrelationId(_headerContext);
}
