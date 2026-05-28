// <copyright file="DesignArchitectureTests.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

namespace Norge360.Repository.EntityFrameworkCore.Architecture.Tests;

public class DesignArchitectureTests
{
    [Fact]
    public void EfRepository_should_be_sealed()
    {
        Assert.True(typeof(Norge360.Repository.EntityFrameworkCore.EfRepository<object, object>).IsSealed);
    }
}