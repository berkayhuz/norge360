// <copyright file="ApiCorsOptions.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using System.ComponentModel.DataAnnotations;

namespace Norge360.Auth.API.Security;

public sealed class ApiCorsOptions
{
    public const string SectionName = "Security:Cors";
    public const string PolicyName = "auth-cors";

    [MinLength(1)]
    public string[] AllowedOrigins { get; set; } = [];

    public bool AllowCredentials { get; set; } = true;
}
