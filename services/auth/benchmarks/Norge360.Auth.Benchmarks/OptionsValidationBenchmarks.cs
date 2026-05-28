// <copyright file="OptionsValidationBenchmarks.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using BenchmarkDotNet.Attributes;
using Microsoft.Extensions.FileProviders;
using Microsoft.Extensions.Hosting;
using Norge360.AspNetCore.TrustedGateway.Options;
using Norge360.Auth.API.Security;
using Norge360.Auth.Application.Options;

namespace Norge360.Auth.Benchmarks;

[MemoryDiagnoser]
public class OptionsValidationBenchmarks
{
    private ApiCorsOptionsValidation _corsValidation = default!;
    private ApiForwardedHeadersOptionsValidation _forwardedHeadersValidation = default!;
    private ApiSecurityHeadersOptionsValidation _securityHeadersValidation = default!;
    private TenantResolutionOptionsValidation _tenantResolutionValidation = default!;
    private AuthRateLimitingOptionsValidation _rateLimitingValidation = default!;
    private TokenTransportOptionsValidation _tokenTransportValidation = default!;
    private AuthTrustedGatewayOptionsValidation _trustedGatewayValidation = default!;
    private AuthorizationOptionsValidation _authorizationOptionsValidation = default!;
    private InvitationDeliveryOptions _invitationDeliveryOptions = default!;

    private ApiCorsOptions _corsOptions = default!;
    private ApiForwardedHeadersOptions _forwardedHeadersOptions = default!;
    private ApiSecurityHeadersOptions _securityHeadersOptions = default!;
    private TenantResolutionOptions _tenantResolutionOptions = default!;
    private AuthRateLimitingOptions _rateLimitingOptions = default!;
    private TokenTransportOptions _tokenTransportOptions = default!;
    private TrustedGatewayOptions _trustedGatewayOptions = default!;
    private AuthorizationOptions _authorizationOptions = default!;

    [GlobalSetup]
    public void Setup()
    {
        var devEnvironment = new BenchmarkHostEnvironment();

        _corsValidation = new ApiCorsOptionsValidation(devEnvironment);
        _forwardedHeadersValidation = new ApiForwardedHeadersOptionsValidation(devEnvironment);
        _securityHeadersValidation = new ApiSecurityHeadersOptionsValidation();
        _tenantResolutionValidation = new TenantResolutionOptionsValidation(devEnvironment);
        _rateLimitingValidation = new AuthRateLimitingOptionsValidation();
        _tokenTransportValidation = new TokenTransportOptionsValidation(devEnvironment);
        _trustedGatewayValidation = new AuthTrustedGatewayOptionsValidation(devEnvironment);
        _authorizationOptionsValidation = new AuthorizationOptionsValidation();

        _corsOptions = new ApiCorsOptions
        {
            AllowedOrigins = ["https://app.norge360.test"],
            AllowCredentials = true
        };

        _forwardedHeadersOptions = new ApiForwardedHeadersOptions
        {
            KnownProxies = ["10.10.0.10"],
            KnownNetworks = ["10.10.0.0/16"]
        };

        _securityHeadersOptions = new ApiSecurityHeadersOptions
        {
            ContentSecurityPolicy = "default-src 'none'; frame-ancestors 'none'; frame-src 'none'; base-uri 'none'; object-src 'none'; form-action 'none';",
            ReferrerPolicy = "no-referrer",
            PermissionsPolicy = "camera=(), microphone=()"
        };

        _tenantResolutionOptions = new TenantResolutionOptions
        {
            HeaderName = "X-Tenant-Id",
            SlugHeaderName = "X-Tenant-Slug",
            TenantOptionalPathPrefixes = ["/api/auth/register"],
            AllowBodyFallback = true,
            RequireResolvedTenant = false,
            TrustedHostSuffixes = [".norge360.test"]
        };

        _rateLimitingOptions = new AuthRateLimitingOptions();

        _tokenTransportOptions = new TokenTransportOptions
        {
            Mode = TokenTransportModes.CookiesOnly,
            SameSite = "Lax",
            AccessCookieName = "__Secure-Norge360-access",
            RefreshCookieName = "__Secure-Norge360-refresh",
            SessionCookieName = "__Secure-Norge360-session"
        };

        _trustedGatewayOptions = new TrustedGatewayOptions
        {
            RequireTrustedGateway = true,
            AllowedSources = ["Norge360.Account"],
            AllowedClockSkewSeconds = 30,
            ReplayProtectionWindowSeconds = 120,
            AllowedGatewayProxies = ["10.10.0.10"],
            CurrentKeyId = "gateway-local-key-2026-01",
            Keys =
            [
                new TrustedGatewayKeyOptions
                {
                    KeyId = "gateway-local-key-2026-01",
                    Secret = "abcdefghijklmnopqrstuvwxyz0123456789",
                    Enabled = true
                }
            ]
        };

        _authorizationOptions = new AuthorizationOptions
        {
            DefaultRoles = ["tenant-user"],
            DefaultPermissions = ["session:self", "profile:self"],
            BootstrapFirstUserRoles = ["tenant-owner", "tenant-admin", "tenant-user"],
            BootstrapFirstUserPermissions = ["*"],
            Policies =
            [
                new PolicyDefinition
                {
                    Name = "tenant-user",
                    RequiredPermissions = ["session:self"],
                    RequiredRoles = ["tenant-user"]
                }
            ]
        };

        _invitationDeliveryOptions = new InvitationDeliveryOptions
        {
            AcceptBaseUrl = "https://app.norge360.test",
            AcceptPath = "/invite/accept"
        };
    }

    [Benchmark] public object Validate_ApiCorsOptions() => _corsValidation.Validate(name: null, _corsOptions);
    [Benchmark] public object Validate_ApiForwardedHeadersOptions() => _forwardedHeadersValidation.Validate(name: null, _forwardedHeadersOptions);
    [Benchmark] public object Validate_ApiSecurityHeadersOptions() => _securityHeadersValidation.Validate(name: null, _securityHeadersOptions);
    [Benchmark] public object Validate_TenantResolutionOptions() => _tenantResolutionValidation.Validate(name: null, _tenantResolutionOptions);
    [Benchmark] public object Validate_AuthRateLimitingOptions() => _rateLimitingValidation.Validate(name: null, _rateLimitingOptions);
    [Benchmark] public object Validate_TokenTransportOptions() => _tokenTransportValidation.Validate(name: null, _tokenTransportOptions);
    [Benchmark] public object Validate_AuthTrustedGatewayOptions() => _trustedGatewayValidation.Validate(name: null, _trustedGatewayOptions);
    [Benchmark] public object Validate_AuthorizationOptions() => _authorizationOptionsValidation.Validate(name: null, _authorizationOptions);
    [Benchmark] public string Build_Invitation_Accept_Url() => _invitationDeliveryOptions.BuildAcceptUrl(Guid.NewGuid(), "token-value", "tester@example.test");

    private sealed class BenchmarkHostEnvironment : IHostEnvironment
    {
        public string EnvironmentName { get; set; } = Environments.Development;
        public string ApplicationName { get; set; } = "Norge360.Auth.Benchmarks";
        public string ContentRootPath { get; set; } = AppContext.BaseDirectory;
        public IFileProvider ContentRootFileProvider { get; set; } = new NullFileProvider();
    }
}
