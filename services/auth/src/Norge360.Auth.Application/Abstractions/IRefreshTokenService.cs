// <copyright file="IRefreshTokenService.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using Norge360.Auth.Application.Descriptors;

namespace Norge360.Auth.Application.Abstractions;

public interface IRefreshTokenService
{
    RefreshTokenDescriptor Generate(bool isPersistent);
    bool Verify(string refreshToken, string refreshTokenHash);
}
