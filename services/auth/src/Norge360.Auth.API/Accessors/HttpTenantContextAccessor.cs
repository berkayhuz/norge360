// <copyright file="HttpTenantContextAccessor.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using Norge360.Auth.API.Middlewares;
using Norge360.Auth.Application.Abstractions;
using Norge360.Auth.Application.Records;

namespace Norge360.Auth.API.Accessors;

public sealed class HttpTenantContextAccessor(IHttpContextAccessor httpContextAccessor) : ITenantContextAccessor
{
    public TenantContext? Current => httpContextAccessor.HttpContext is null
        ? null
        : TenantResolutionMiddleware.GetTenantContext(httpContextAccessor.HttpContext);
}
