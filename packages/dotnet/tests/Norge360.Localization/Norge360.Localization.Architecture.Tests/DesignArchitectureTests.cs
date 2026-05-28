// <copyright file="DesignArchitectureTests.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>
namespace Norge360.Localization.Architecture.Tests;

public class DesignArchitectureTests
{
    [Fact]
    public void Norge360Cultures_should_remain_static()
    {
        var type = typeof(Norge360.Localization.Norge360Cultures);
        Assert.True(type.IsAbstract && type.IsSealed, "Norge360Cultures should remain static.");
    }
}
