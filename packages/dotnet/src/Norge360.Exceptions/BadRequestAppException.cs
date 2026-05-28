// <copyright file="BadRequestAppException.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using System.ComponentModel.DataAnnotations;

namespace Norge360.Exceptions;

public class BadRequestAppException : ValidationException
{
    public BadRequestAppException(string message) : base(message) { }
}
