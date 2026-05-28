// <copyright file="Program.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using BenchmarkDotNet.Configs;
using BenchmarkDotNet.Running;
using Norge360.AspNetCore.Benchmarks;

var config = DefaultConfig.Instance;
BenchmarkSwitcher
    .FromAssembly(typeof(Program).Assembly)
    .Run(args, config);
