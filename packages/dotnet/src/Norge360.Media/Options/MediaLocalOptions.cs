// <copyright file="MediaLocalOptions.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

namespace Norge360.Media.Options;

public sealed class MediaLocalOptions
{
    public string RootPath { get; init; } = ".runlogs/media";
    public string RequestPath { get; init; } = "/uploads";
}
