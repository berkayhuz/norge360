// <copyright file="IRecoveryCodeService.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

namespace Norge360.Auth.Application.Abstractions;

public interface IRecoveryCodeService
{
    IReadOnlyCollection<string> GenerateCodes(int count);
    string HashCode(Guid userId, string code);
}
