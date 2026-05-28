// <copyright file="ArchitectureTestAssembly.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using System.Reflection;

namespace Norge360.Security.EndpointGuard.Architecture.Tests;

internal static class ArchitectureTestAssembly
{
    internal static readonly Assembly ProductionAssembly = typeof(Norge360.Security.EndpointGuard.ExternalEndpointGuard).Assembly;
}