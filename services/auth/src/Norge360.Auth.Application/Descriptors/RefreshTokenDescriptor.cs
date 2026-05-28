// <copyright file="RefreshTokenDescriptor.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

namespace Norge360.Auth.Application.Descriptors;

public sealed record RefreshTokenDescriptor(string Token, string Hash, DateTime ExpiresAtUtc);
