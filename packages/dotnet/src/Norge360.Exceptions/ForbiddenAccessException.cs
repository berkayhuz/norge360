// <copyright file="ForbiddenAccessException.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

namespace Norge360.Exceptions;

public class ForbiddenAccessException : Exception
{
    public ForbiddenAccessException() : base("Forbidden access.") { }
    public ForbiddenAccessException(string message) : base(message) { }
}
