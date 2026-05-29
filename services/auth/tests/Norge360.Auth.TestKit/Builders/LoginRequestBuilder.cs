// <copyright file="LoginRequestBuilder.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using Norge360.Auth.Contracts.Requests;

namespace Norge360.Auth.TestKit.Builders;

public sealed class LoginRequestBuilder
{
    private string _emailOrUserName = "jane.doe@example.com";
    private string _password = "StrongPassword123!";
    private bool _rememberMe;
    private string? _mfaCode;
    private string? _recoveryCode;

    public LoginRequestBuilder WithMfaCode(string mfaCode)
    {
        _mfaCode = mfaCode;
        _recoveryCode = null;
        return this;
    }

    public LoginRequestBuilder WithRecoveryCode(string recoveryCode)
    {
        _recoveryCode = recoveryCode;
        _mfaCode = null;
        return this;
    }

    public LoginRequestBuilder WithCredentials(string emailOrUserName, string password)
    {
        _emailOrUserName = emailOrUserName;
        _password = password;
        return this;
    }

    public LoginRequestBuilder WithRememberMe(bool rememberMe = true)
    {
        _rememberMe = rememberMe;
        return this;
    }

    public LoginRequest Build() => new(_emailOrUserName, _password, _rememberMe, _mfaCode, _recoveryCode);
}
