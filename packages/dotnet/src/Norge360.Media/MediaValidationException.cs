// <copyright file="MediaValidationException.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

namespace Norge360.Media;

public sealed class MediaValidationException : Exception
{
    public MediaValidationException(string message)
        : base(message)
    {
    }

    public MediaValidationException(string message, Exception innerException)
        : base(message, innerException)
    {
    }
}
