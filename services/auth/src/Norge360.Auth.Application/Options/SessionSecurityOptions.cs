// <copyright file="SessionSecurityOptions.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

namespace Norge360.Auth.Application.Options;

public sealed class SessionSecurityOptions
{
    public const string SectionName = "SessionSecurity";

    public int MaxActiveSessions { get; set; } = 5;

    public int IdleTimeoutMinutes { get; set; } = 60 * 24;

    public int AbsoluteLifetimeDays { get; set; } = 14;
}
