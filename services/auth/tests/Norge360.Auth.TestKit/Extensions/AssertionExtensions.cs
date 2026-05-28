// <copyright file="AssertionExtensions.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using System.Net;
using FluentAssertions;

namespace Norge360.Auth.TestKit.Extensions;

public static class AssertionExtensions
{
    public static void ShouldHaveStatus(this HttpResponseMessage response, HttpStatusCode expected)
    {
        response.StatusCode.Should().Be(expected);
    }
}

