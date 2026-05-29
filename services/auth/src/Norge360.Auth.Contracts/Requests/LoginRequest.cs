// <copyright file="LoginRequest.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

namespace Norge360.Auth.Contracts.Requests;

public sealed record LoginRequest(
    string EmailOrUserName,
    string Password,
    bool RememberMe = false,
    string? MfaCode = null,
    string? RecoveryCode = null);
