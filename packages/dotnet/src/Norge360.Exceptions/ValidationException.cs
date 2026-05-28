// <copyright file="ValidationException.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

namespace Norge360.Exceptions;

public class ValidationException : Exception
{
    public IReadOnlyDictionary<string, string[]> Errors { get; } = new Dictionary<string, string[]>();

    public ValidationException(string message) : base(message) { }
    public ValidationException(string message, IDictionary<string, string[]> errors) : base(message)
        => Errors = new Dictionary<string, string[]>(errors);
}
