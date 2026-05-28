// <copyright file="IAuthAuditTrail.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using Norge360.Auth.Application.Records;

namespace Norge360.Auth.Application.Abstractions;

public interface IAuthAuditTrail
{
    Task WriteAsync(AuthAuditRecord record, CancellationToken cancellationToken);
}
