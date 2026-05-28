// <copyright file="ModelBuilderExtensions.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using Microsoft.EntityFrameworkCore;

namespace Norge360.Persistence.EntityFrameworkCore;

public static class ModelBuilderExtensions
{
    public static ModelBuilder ApplyDefaultDecimalPrecision(this ModelBuilder modelBuilder, int precision = 18, int scale = 2)
    {
        foreach (var property in modelBuilder.Model.GetEntityTypes().SelectMany(x => x.GetProperties()))
        {
            var clrType = Nullable.GetUnderlyingType(property.ClrType) ?? property.ClrType;

            if (clrType != typeof(decimal))
            {
                continue;
            }

            property.SetPrecision(precision);
            property.SetScale(scale);
        }

        return modelBuilder;
    }
}
