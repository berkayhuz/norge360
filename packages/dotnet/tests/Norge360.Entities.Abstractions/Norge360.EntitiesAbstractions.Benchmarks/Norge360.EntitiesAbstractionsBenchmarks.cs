// <copyright file="Norge360.EntitiesAbstractionsBenchmarks.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using BenchmarkDotNet.Attributes;
using Norge360.Entities.Abstractions;

namespace Norge360.Entities.Abstractions.Benchmarks;

[MemoryDiagnoser]
[InProcess]
public class Norge360EntitiesAbstractionsBenchmarks
{
    private readonly AuditableModel _model = new();

    [Benchmark(Baseline = true)]
    public DateTime ReadCreatedAt() => _model.CreatedAt;

    [Benchmark]
    public void WriteUpdatedAt() => _model.UpdatedAt = DateTime.UtcNow;

    [Benchmark]
    public void WriteDeletedFlag() => _model.IsDeleted = true;

    [Benchmark]
    public int ReadRowVersionLength() => _model.RowVersion.Length;

    private sealed class AuditableModel : IAuditable, IHasRowVersion, ISoftDeletable, ITenantEntity
    {
        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
        public string? CreatedBy { get; set; }
        public string? UpdatedBy { get; set; }
        public byte[] RowVersion { get; set; } = [1, 2, 3, 4, 5, 6, 7, 8];
        public bool IsDeleted { get; set; }
        public DateTime? DeletedAt { get; set; }
        public string? DeletedBy { get; set; }
        public Guid TenantId { get; set; }
    }
}
