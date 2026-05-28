// <copyright file="ITokenSigningKeyProvider.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using Microsoft.IdentityModel.Tokens;

namespace Norge360.Auth.Application.Abstractions;

public interface ITokenSigningKeyProvider
{
    SigningCredentials GetCurrentSigningCredentials();

    IReadOnlyCollection<SecurityKey> GetValidationKeys();

    string CurrentKeyId { get; }

    object GetJwksDocument(string issuer);
}
