// <copyright file="AuthCookieServiceBenchmarks.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using BenchmarkDotNet.Attributes;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Options;
using Norge360.Auth.API.Cookies;
using Norge360.Auth.Application.Options;
using Norge360.Auth.Contracts.Responses;

namespace Norge360.Auth.Benchmarks;

[MemoryDiagnoser]
public class AuthCookieServiceBenchmarks
{
    private AuthCookieService _cookieModeService = default!;
    private AuthCookieService _bodyModeService = default!;
    private AuthenticationTokenResponse _token = default!;
    private HttpResponse _response = default!;

    [GlobalSetup]
    public void Setup()
    {
        _cookieModeService = new AuthCookieService(Options.Create(new TokenTransportOptions
        {
            Mode = TokenTransportModes.CookiesOnly
        }));

        _bodyModeService = new AuthCookieService(Options.Create(new TokenTransportOptions
        {
            Mode = TokenTransportModes.BodyOnly
        }));

        _token = new AuthenticationTokenResponse(
            "access-token",
            DateTime.UtcNow.AddMinutes(15),
            "refresh-token",
            DateTime.UtcNow.AddDays(14),
            Guid.NewGuid(),
            Guid.NewGuid(),
            "tester",
            "tester@example.test",
            Guid.NewGuid(),
            IsPersistent: true);

        var context = new DefaultHttpContext();
        context.Request.Scheme = "https";
        _response = context.Response;
    }

    [Benchmark]
    public object CreateResponsePayload_CookiesOnly() => _cookieModeService.CreateResponsePayload(_token);

    [Benchmark]
    public object CreateResponsePayload_BodyOnly() => _bodyModeService.CreateResponsePayload(_token);

    [Benchmark]
    public void Apply_CookiesOnly() => _cookieModeService.Apply(_response, _token);

    [Benchmark]
    public void Clear_CookiesOnly() => _cookieModeService.Clear(_response);
}

