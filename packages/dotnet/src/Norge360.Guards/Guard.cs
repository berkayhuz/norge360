// <copyright file="Guard.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

namespace Norge360.Guards;

public static class Guard
{
    public static string AgainstNullOrWhiteSpace(string? value, string? parameterName = null)
        => string.IsNullOrWhiteSpace(value)
            ? throw new ArgumentException("Value cannot be null or whitespace.", parameterName ?? nameof(value))
            : value.Trim();

    public static T AgainstNull<T>(T? value, string? parameterName = null)
        where T : class
        => value ?? throw new ArgumentNullException(parameterName ?? nameof(value));

    public static Guid AgainstEmpty(Guid value, string? parameterName = null)
        => value == Guid.Empty ? throw new ArgumentException("Value cannot be empty.", parameterName ?? nameof(value)) : value;
}
