// <copyright file="CurrentUserCoreBenchmarks.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using BenchmarkDotNet.Attributes;
using Norge360.CurrentUser;

namespace Norge360.AspNetCore.Benchmarks;

[MemoryDiagnoser]
public class CurrentUserCoreBenchmarks
{
    private readonly ICurrentUserService _authenticated = new StubCurrentUserService { UserId = Guid.Parse("d2501385-53f6-483f-a17f-8c1bc37da6ea"), TenantId = Guid.Parse("9dcb7547-aab7-4d65-8bf1-0a7393f7d4e8") };

    [Benchmark(Baseline = true)]
    public bool IsAuthenticated() => _authenticated.IsAuthenticated();

    [Benchmark]
    public Guid EnsureAuthenticated() => _authenticated.EnsureAuthenticated();

    private sealed class StubCurrentUserService : ICurrentUserService
    {
        public Guid UserId { get; init; }
        public Guid TenantId { get; init; }
        public bool IsAuthenticated => UserId != Guid.Empty;
        public string? UserName => null;
        public string? Email => null;
        public IReadOnlyCollection<string> Roles => [];
        public IReadOnlyCollection<string> Permissions => [];
        public bool IsInRole(string role) => false;
        public bool HasPermission(string permission) => false;
    }
}
