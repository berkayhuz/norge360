// <copyright file="PageRequest.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

namespace Norge360.Pagination;

public sealed record PageRequest(int PageNumber, int PageSize)
{
    public int Page => PageNumber;
    public int Size => PageSize;
    public int Skip => (PageNumber - 1) * PageSize;

    public static PageRequest Normalize(int pageNumber, int pageSize)
        => new(Math.Max(1, pageNumber), Math.Clamp(pageSize, 1, 200));

    public static PageRequest Normalize(int? pageNumber, int? pageSize)
        => Normalize(pageNumber ?? 1, pageSize ?? 20);
}
