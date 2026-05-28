// <copyright file="DesignArchitectureTests.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>
namespace Norge360.Media.Storage.Architecture.Tests;

public class DesignArchitectureTests
{
    [Fact]
    public void MediaServiceCollectionExtensions_should_remain_static()
    {
        var type = typeof(Norge360.Media.Storage.MediaServiceCollectionExtensions);
        Assert.True(type.IsAbstract && type.IsSealed, "MediaServiceCollectionExtensions should remain static.");
    }
}
