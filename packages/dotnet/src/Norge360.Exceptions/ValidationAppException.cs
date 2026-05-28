// <copyright file="ValidationAppException.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

namespace Norge360.Exceptions;

public class ValidationAppException : ValidationException
{
    public ValidationAppException(string message) : base(message) { }
    public ValidationAppException(string message, IDictionary<string, string[]> errors) : base(message, errors) { }
}
