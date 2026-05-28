// <copyright file="MediaUploadRequest.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

namespace Norge360.Media.Models;

public sealed record MediaUploadRequest(
    string TenantId,
    string Purpose,
    string? OwnerUserId,
    string OriginalFileName,
    string ContentType,
    Stream Content,
    long Length,
    string Module);
