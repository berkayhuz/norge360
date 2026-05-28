// <copyright file="DesignArchitectureTests.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>
namespace Norge360.Messaging.RabbitMq.Architecture.Tests;

public class DesignArchitectureTests
{
    [Fact]
    public void Dependency_injection_extensions_should_be_static()
    {
        var type = typeof(Norge360.Messaging.RabbitMq.DependencyInjection.RabbitMqServiceCollectionExtensions);
        Assert.True(type.IsAbstract && type.IsSealed, "RabbitMqServiceCollectionExtensions should remain static.");
    }
}
