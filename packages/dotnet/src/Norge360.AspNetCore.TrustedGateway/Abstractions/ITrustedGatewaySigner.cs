// <copyright file="ITrustedGatewaySigner.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using Microsoft.AspNetCore.Http;
using Norge360.AspNetCore.TrustedGateway.Models;

namespace Norge360.AspNetCore.TrustedGateway.Abstractions;

public interface ITrustedGatewaySigner
{
    Task<TrustedGatewaySignedHeaders> SignAsync(HttpRequest request, string correlationId, CancellationToken cancellationToken);
}
