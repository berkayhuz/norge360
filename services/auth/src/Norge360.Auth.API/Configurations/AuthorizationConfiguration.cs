// <copyright file="AuthorizationConfiguration.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using Microsoft.AspNetCore.Authorization;
using Norge360.Auth.API.Permissions;
using Norge360.Auth.API.Security;
using AuthorizationOptions = Norge360.Auth.Application.Options.AuthorizationOptions;

namespace Norge360.Auth.API.Configurations;

public static class AuthorizationConfiguration
{
    public static IServiceCollection AddNorge360Authorization(
        this IServiceCollection services,
        AuthorizationOptions options)
    {
        services.AddSingleton<IAuthorizationHandler, PermissionAuthorizationHandler>();
        services.AddSingleton<IAuthorizationHandler, TrustedInternalSourceAuthorizationHandler>();

        services.AddAuthorization(builder =>
        {
            builder.AddPolicy(AuthAuthorizationPolicies.PlatformUser, policy =>
            {
                policy.RequireAuthenticatedUser();
            });

            builder.AddPolicy(AuthAuthorizationPolicies.InternalService, policy =>
            {
                policy.Requirements.Add(new TrustedInternalSourceRequirement());
            });

            foreach (var definition in options.Policies)
            {
                builder.AddPolicy(definition.Name, policy =>
                {
                    if (definition.RequireAuthenticatedUser)
                    {
                        policy.RequireAuthenticatedUser();
                    }

                    foreach (var permission in definition.RequiredPermissions)
                    {
                        policy.Requirements.Add(new PermissionRequirement(permission));
                    }

                    if (definition.RequiredRoles.Length > 0)
                    {
                        policy.RequireRole(definition.RequiredRoles);
                    }
                });
            }
        });

        return services;
    }
}
