// <copyright file="ArchitectureTestAssembly.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using System.Reflection;

namespace Norge360.AspNetCore.Architecture.Tests;

internal static class ArchitectureTestAssembly
{
    internal const string ProductionRootNamespace = "Norge360.AspNetCore";

    internal static Assembly ProductionAssembly => typeof(Norge360.AspNetCore.Health.HealthResponseWriter).Assembly;
}
