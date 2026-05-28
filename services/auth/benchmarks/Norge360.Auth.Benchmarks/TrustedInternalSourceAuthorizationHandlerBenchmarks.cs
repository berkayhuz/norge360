// <copyright file="TrustedInternalSourceAuthorizationHandlerBenchmarks.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using System.Security.Claims;
using BenchmarkDotNet.Attributes;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Options;
using Norge360.AspNetCore.TrustedGateway.Options;
using Norge360.Auth.API.Middlewares;
using Norge360.Auth.API.Security;

namespace Norge360.Auth.Benchmarks;

[MemoryDiagnoser]
public class TrustedInternalSourceAuthorizationHandlerBenchmarks
{
    private TrustedInternalSourceAuthorizationHandler _allowHandler = default!;
    private TrustedInternalSourceAuthorizationHandler _denyHandler = default!;
    private AuthorizationHandlerContext _allowContext = default!;
    private AuthorizationHandlerContext _denyContext = default!;

    [GlobalSetup]
    public void Setup()
    {
        var internalIdentityOptions = Options.Create(new InternalIdentityOptions
        {
            AllowedSources = ["internal-gateway"]
        });
        var trustedGatewayOptions = Options.Create(new TrustedGatewayOptions
        {
            RequireTrustedGateway = true,
            SourceHeaderName = "X-Source"
        });

        var allowContext = new DefaultHttpContext();
        allowContext.Items[TrustedGatewayMiddleware.TrustedGatewayValidatedItemName] = true;
        allowContext.Request.Headers["X-Source"] = "internal-gateway";

        var denyContext = new DefaultHttpContext();
        denyContext.Request.Headers["X-Source"] = "internal-gateway";

        _allowHandler = new TrustedInternalSourceAuthorizationHandler(
            new HttpContextAccessor { HttpContext = allowContext },
            internalIdentityOptions,
            trustedGatewayOptions);
        _denyHandler = new TrustedInternalSourceAuthorizationHandler(
            new HttpContextAccessor { HttpContext = denyContext },
            internalIdentityOptions,
            trustedGatewayOptions);

        _allowContext = CreateAuthContext();
        _denyContext = CreateAuthContext();
    }

    [Benchmark]
    public Task Allow_TrustedGateway_And_AllowedSource() => _allowHandler.HandleAsync(_allowContext);

    [Benchmark]
    public Task Deny_When_Not_TrustedGatewayRequest() => _denyHandler.HandleAsync(_denyContext);

    private static AuthorizationHandlerContext CreateAuthContext()
    {
        var principal = new ClaimsPrincipal(new ClaimsIdentity(authenticationType: "bench"));
        return new AuthorizationHandlerContext([new TrustedInternalSourceRequirement()], principal, resource: null);
    }
}
