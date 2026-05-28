// <copyright file="DesignArchitectureTests.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

namespace Norge360.Security.EndpointGuard.Architecture.Tests;

public class DesignArchitectureTests
{
    [Fact]
    public void ExternalEndpointGuard_should_be_static()
    {
        var type = typeof(Norge360.Security.EndpointGuard.ExternalEndpointGuard); Assert.True(type.IsAbstract && type.IsSealed);
    }
}