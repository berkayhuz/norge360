// <copyright file="AuthRequestContextAccessorBenchmarks.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using BenchmarkDotNet.Attributes;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Options;
using Norge360.Auth.API.Accessors;
using Norge360.Auth.API.Cookies;
using Norge360.Auth.Application.Abstractions;
using Norge360.Auth.Application.Options;
using Norge360.Auth.Application.Records;
using Norge360.Auth.Contracts.Responses;

namespace Norge360.Auth.Benchmarks;

[MemoryDiagnoser]
public class AuthRequestContextAccessorBenchmarks
{
    private AuthRequestContextAccessor _trustedAccessor = default!;
    private AuthRequestContextAccessor _bodyFallbackAccessor = default!;
    private AuthRequestContextAccessor _refreshCookieAccessor = default!;
    private HttpRequest _request = default!;
    private ClaimsPrincipal _principal = default!;
    private Guid _tenantId;
    private Guid _sessionId;

    [GlobalSetup]
    public void Setup()
    {
        _tenantId = Guid.NewGuid();
        _sessionId = Guid.NewGuid();

        var tokenOptions = new TokenTransportOptions
        {
            Mode = TokenTransportModes.CookiesOnly,
            AllowRefreshTokenFromRequestBody = true,
            AllowSessionIdFromRequestBody = true,
            RefreshCookieName = "__Secure-Norge360-refresh",
            SessionCookieName = "__Secure-Norge360-session"
        };

        var cookieService = new AuthCookieService(Options.Create(tokenOptions));

        _trustedAccessor = new AuthRequestContextAccessor(
            new StaticTenantContextAccessor(new TenantContext(_tenantId, null, "header", true)),
            Options.Create(new TenantResolutionOptions { AllowBodyFallback = false }),
            Options.Create(tokenOptions),
            cookieService);

        _bodyFallbackAccessor = new AuthRequestContextAccessor(
            new StaticTenantContextAccessor(null),
            Options.Create(new TenantResolutionOptions { AllowBodyFallback = true }),
            Options.Create(tokenOptions),
            cookieService);

        _refreshCookieAccessor = new AuthRequestContextAccessor(
            new StaticTenantContextAccessor(null),
            Options.Create(new TenantResolutionOptions { AllowBodyFallback = true }),
            Options.Create(tokenOptions),
            cookieService);

        var context = new DefaultHttpContext();
        context.Request.Headers.Cookie = $"__Secure-Norge360-refresh=refresh-token; __Secure-Norge360-session={_sessionId:D}";
        _request = context.Request;

        _principal = new ClaimsPrincipal(new ClaimsIdentity(
        [
            new Claim("tenant_id", _tenantId.ToString("D")),
            new Claim(ClaimTypes.NameIdentifier, Guid.NewGuid().ToString("D")),
            new Claim(JwtRegisteredClaimNames.Sid, _sessionId.ToString("D")),
            new Claim(ClaimTypes.Email, "tester@example.test")
        ], "bench"));
    }

    [Benchmark]
    public Guid ResolveTenantId_From_Trusted_Context() => _trustedAccessor.ResolveTenantId(Guid.Empty);

    [Benchmark]
    public Guid ResolveTenantId_From_Body_Fallback() => _bodyFallbackAccessor.ResolveTenantId(_tenantId);

    [Benchmark]
    public (Guid SessionId, string RefreshToken) ResolveRefreshContext_From_Cookies() =>
        _refreshCookieAccessor.ResolveRefreshContext(_request, Guid.Empty, requestedRefreshToken: null);

    [Benchmark]
    public PrincipalContext GetPrincipalContext_From_Claims() => _trustedAccessor.GetPrincipalContext(_principal);

    private sealed class StaticTenantContextAccessor(TenantContext? current) : ITenantContextAccessor
    {
        public TenantContext? Current => current;
    }
}

