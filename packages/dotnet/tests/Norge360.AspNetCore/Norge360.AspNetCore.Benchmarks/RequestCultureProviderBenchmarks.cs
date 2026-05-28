// <copyright file="RequestCultureProviderBenchmarks.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using BenchmarkDotNet.Attributes;
using Microsoft.AspNetCore.Http;
using Norge360.AspNetCore.Localization.Providers;
using Norge360.Localization;

namespace Norge360.AspNetCore.Benchmarks;

[MemoryDiagnoser]
public class RequestCultureProviderBenchmarks
{
    private readonly Norge360HeaderRequestCultureProvider _headerProvider = new();
    private readonly Norge360CookieRequestCultureProvider _cookieProvider = new();
    private readonly Norge360AcceptLanguageRequestCultureProvider _acceptLanguageProvider = new();

    private DefaultHttpContext _headerContext = null!;
    private DefaultHttpContext _cookieContext = null!;
    private DefaultHttpContext _cookieFrameworkFormatContext = null!;
    private DefaultHttpContext _acceptLanguageContext = null!;

    [GlobalSetup]
    public void Setup()
    {
        _headerContext = new DefaultHttpContext();
        _headerContext.Request.Headers[Norge360Cultures.HeaderName] = "tr-TR";

        _cookieContext = new DefaultHttpContext();
        _cookieContext.Request.Headers.Cookie = $"{Norge360Cultures.CookieName}=tr-TR";

        _cookieFrameworkFormatContext = new DefaultHttpContext();
        _cookieFrameworkFormatContext.Request.Headers.Cookie = $"{Norge360Cultures.CookieName}=c=tr-TR|uic=tr-TR";

        _acceptLanguageContext = new DefaultHttpContext();
        _acceptLanguageContext.Request.Headers.AcceptLanguage = "tr-TR,tr;q=0.9,en-US;q=0.7,en;q=0.5";
    }

    [Benchmark]
    public Task HeaderProvider_DetermineProviderCultureResult() =>
        _headerProvider.DetermineProviderCultureResult(_headerContext);

    [Benchmark]
    public Task CookieProvider_DetermineProviderCultureResult() =>
        _cookieProvider.DetermineProviderCultureResult(_cookieContext);

    [Benchmark]
    public Task CookieProvider_DetermineProviderCultureResult_FrameworkCookieFormat() =>
        _cookieProvider.DetermineProviderCultureResult(_cookieFrameworkFormatContext);

    [Benchmark]
    public Task AcceptLanguageProvider_DetermineProviderCultureResult() =>
        _acceptLanguageProvider.DetermineProviderCultureResult(_acceptLanguageContext);
}
