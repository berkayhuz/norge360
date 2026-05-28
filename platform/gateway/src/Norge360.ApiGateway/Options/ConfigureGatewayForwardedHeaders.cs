// <copyright file="ConfigureGatewayForwardedHeaders.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using Microsoft.Extensions.Options;
using Norge360.AspNetCore.Security;

namespace Norge360.ApiGateway.Options;

public sealed class ConfigureGatewayForwardedHeaders(IOptions<GatewayForwardedHeadersOptions> options)
    : IConfigureOptions<ForwardedHeadersOptions>
{
    public void Configure(ForwardedHeadersOptions forwardedHeadersOptions)
    {
        var value = options.Value;
        SecuritySupport.ConfigureForwardedHeaders(
            forwardedHeadersOptions,
            value.ForwardLimit,
            value.KnownProxies,
            value.KnownNetworks);
    }
}
