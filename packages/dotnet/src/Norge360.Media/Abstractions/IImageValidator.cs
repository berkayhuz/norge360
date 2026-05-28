// <copyright file="IImageValidator.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using Norge360.Media.Models;

namespace Norge360.Media.Abstractions;

public interface IImageValidator
{
    Task<ImageValidationResult> ValidateAsync(string fileName, string declaredContentType, Stream content, long length, CancellationToken cancellationToken);
}
