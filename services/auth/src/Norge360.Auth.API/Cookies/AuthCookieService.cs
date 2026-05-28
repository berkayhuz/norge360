// <copyright file="AuthCookieService.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using Microsoft.Extensions.Options;
using Norge360.Auth.Application.Options;
using Norge360.Auth.Contracts.Responses;

namespace Norge360.Auth.API.Cookies;

public sealed class AuthCookieService(IOptions<TokenTransportOptions> options)
{
    public string AccessCookieName => options.Value.AccessCookieName;
    public string RefreshCookieName => options.Value.RefreshCookieName;
    public string SessionCookieName => options.Value.SessionCookieName;

    public bool ShouldReturnTokensInBody =>
        string.Equals(options.Value.Mode, TokenTransportModes.BodyOnly, StringComparison.OrdinalIgnoreCase) ||
        string.Equals(options.Value.Mode, TokenTransportModes.HybridDevelopment, StringComparison.OrdinalIgnoreCase);

    public object CreateResponsePayload(AuthenticationTokenResponse tokenResponse)
    {
        if (ShouldReturnTokensInBody)
        {
            return tokenResponse;
        }

        return new AuthIssuedSessionResponse(
            tokenResponse.SessionId,
            tokenResponse.AccessTokenExpiresAt,
            tokenResponse.RefreshTokenExpiresAt,
            tokenResponse.TenantId,
            tokenResponse.UserId,
            tokenResponse.UserName,
            tokenResponse.Email);
    }

    public void Apply(HttpResponse response, AuthenticationTokenResponse tokenResponse)
    {
        var value = options.Value;
        if (string.Equals(value.Mode, TokenTransportModes.BodyOnly, StringComparison.OrdinalIgnoreCase))
        {
            return;
        }

        response.Cookies.Append(
            value.AccessCookieName,
            tokenResponse.AccessToken,
            CreateCookieOptions(tokenResponse.AccessTokenExpiresAt, value.AccessCookieName, value.AccessCookiePath, tokenResponse.IsPersistent, response.HttpContext.Request.IsHttps));

        response.Cookies.Append(
            value.RefreshCookieName,
            tokenResponse.RefreshToken,
            CreateCookieOptions(tokenResponse.RefreshTokenExpiresAt, value.RefreshCookieName, value.RefreshCookiePath, tokenResponse.IsPersistent, response.HttpContext.Request.IsHttps));

        response.Cookies.Append(
            value.SessionCookieName,
            tokenResponse.SessionId.ToString("D"),
            CreateCookieOptions(tokenResponse.RefreshTokenExpiresAt, value.SessionCookieName, value.SessionCookiePath, tokenResponse.IsPersistent, response.HttpContext.Request.IsHttps));
    }

    public void Clear(HttpResponse response)
    {
        var value = options.Value;
        response.Cookies.Delete(value.AccessCookieName, CreateDeleteOptions(value.AccessCookieName, value.AccessCookiePath, response.HttpContext.Request.IsHttps));
        response.Cookies.Delete(value.RefreshCookieName, CreateDeleteOptions(value.RefreshCookieName, value.RefreshCookiePath, response.HttpContext.Request.IsHttps));
        response.Cookies.Delete(value.SessionCookieName, CreateDeleteOptions(value.SessionCookieName, value.SessionCookiePath, response.HttpContext.Request.IsHttps));
    }

    private CookieOptions CreateCookieOptions(DateTime expiresAtUtc, string cookieName, string path, bool isPersistent, bool responseIsHttps)
    {
        var useSecureCookie = ShouldUseSecureCookie(cookieName, responseIsHttps);
        var options = new CookieOptions
        {
            HttpOnly = true,
            Secure = useSecureCookie,
            SameSite = ResolveSameSite(),
            IsEssential = true,
            Path = path,
            Domain = ResolveCookieDomain(cookieName)
        };

        if (isPersistent)
        {
            options.Expires = new DateTimeOffset(DateTime.SpecifyKind(expiresAtUtc, DateTimeKind.Utc));
        }

        return options;
    }

    private CookieOptions CreateDeleteOptions(string cookieName, string path, bool responseIsHttps) => new()
    {
        HttpOnly = true,
        Secure = ShouldUseSecureCookie(cookieName, responseIsHttps),
        SameSite = ResolveSameSite(),
        IsEssential = true,
        Expires = DateTimeOffset.UnixEpoch,
        MaxAge = TimeSpan.Zero,
        Path = path,
        Domain = ResolveCookieDomain(cookieName)
    };

    private string? ResolveCookieDomain(string cookieName) =>
        cookieName.StartsWith("__Host-", StringComparison.Ordinal)
            ? null
            : string.IsNullOrWhiteSpace(options.Value.CookieDomain) ? null : options.Value.CookieDomain;

    private SameSiteMode ResolveSameSite() =>
        Enum.TryParse<SameSiteMode>(options.Value.SameSite, ignoreCase: true, out var parsedSameSite)
            ? parsedSameSite
            : SameSiteMode.Lax;

    private static bool ShouldUseSecureCookie(string cookieName, bool responseIsHttps) =>
        cookieName.StartsWith("__Secure-", StringComparison.Ordinal) ||
        cookieName.StartsWith("__Host-", StringComparison.Ordinal) ||
        responseIsHttps;
}

public sealed record AuthIssuedSessionResponse(
    Guid SessionId,
    DateTime AccessTokenExpiresAt,
    DateTime RefreshTokenExpiresAt,
    Guid TenantId,
    Guid UserId,
    string UserName,
    string Email);
