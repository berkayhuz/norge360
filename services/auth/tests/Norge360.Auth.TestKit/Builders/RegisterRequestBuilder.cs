// <copyright file="RegisterRequestBuilder.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using Norge360.Auth.Contracts.Requests;

namespace Norge360.Auth.TestKit.Builders;

public sealed class RegisterRequestBuilder
{
    private string _tenantName = "Acme Workspace";
    private string _userName = "jane.doe";
    private string _email = "jane.doe@example.com";
    private string _password = "StrongPassword123!";
    private readonly string? _firstName = "Jane";
    private readonly string? _lastName = "Doe";
    private string? _culture = "en-US";

    public RegisterRequestBuilder WithIdentity(string userName, string email)
    {
        _userName = userName;
        _email = email;
        return this;
    }

    public RegisterRequestBuilder WithPassword(string password)
    {
        _password = password;
        return this;
    }

    public RegisterRequestBuilder WithTenantName(string tenantName)
    {
        _tenantName = tenantName;
        return this;
    }

    public RegisterRequestBuilder WithCulture(string? culture)
    {
        _culture = culture;
        return this;
    }

    public RegisterRequest Build() => new(_tenantName, _userName, _email, _password, _firstName, _lastName, _culture);
}
