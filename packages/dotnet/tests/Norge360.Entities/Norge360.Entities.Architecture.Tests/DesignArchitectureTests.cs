// <copyright file="DesignArchitectureTests.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

namespace Norge360.Entities.Architecture.Tests;

public class DesignArchitectureTests
{
    [Fact]
    public void EntityBase_should_remain_abstract()
    {
        Assert.True(typeof(Norge360.Entities.EntityBase).IsAbstract, "EntityBase should remain abstract."
        );
    }

    [Fact]
    public void EntityBase_should_implement_entity_abstractions_contracts()
    {
        var implemented = typeof(Norge360.Entities.EntityBase).GetInterfaces().Select(x => x.FullName).ToArray();

        Assert.Contains("Norge360.Entities.Abstractions.ITenantEntity", implemented);
        Assert.Contains("Norge360.Entities.Abstractions.ISoftDeletable", implemented);
        Assert.Contains("Norge360.Entities.Abstractions.IAuditable", implemented);
        Assert.Contains("Norge360.Entities.Abstractions.IHasRowVersion", implemented);
    }
}
