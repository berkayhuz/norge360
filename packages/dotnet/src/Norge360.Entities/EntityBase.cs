// <copyright file="EntityBase.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using Norge360.Entities.Abstractions;

namespace Norge360.Entities;

public abstract class EntityBase : ISoftDeletable, IAuditable, IHasRowVersion
{
    public Guid Id { get; protected set; } = Guid.NewGuid();
    public DateTime CreatedAt { get; set; }
    public DateTime? UpdatedAt { get; set; }
    public string? CreatedBy { get; set; }
    public string? UpdatedBy { get; set; }
    public bool IsDeleted { get; set; }
    public DateTime? DeletedAt { get; set; }
    public string? DeletedBy { get; set; }
    public byte[] RowVersion { get; set; } = [];
    public bool IsActive { get; protected set; } = true;
    public void SetActive(bool isActive) => IsActive = isActive;
    public void Activate() => SetActive(true);
    public void Deactivate() => SetActive(false);
}
