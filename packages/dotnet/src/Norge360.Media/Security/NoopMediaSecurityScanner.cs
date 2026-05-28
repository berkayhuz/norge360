// <copyright file="NoopMediaSecurityScanner.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using Norge360.Media.Abstractions;
using Norge360.Media.Models;

namespace Norge360.Media.Security;

public sealed class NoopMediaSecurityScanner : IMediaSecurityScanner
{
    public Task<MediaSecurityScanResult> ScanAsync(MediaSecurityScanRequest request, CancellationToken cancellationToken)
        => Task.FromResult(MediaSecurityScanResult.Safe);
}
