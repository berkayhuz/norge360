// <copyright file="20260516090000_EnforceGlobalUniqueUserEmail.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Norge360.Auth.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class EnforceGlobalUniqueUserEmail : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql(
                """
                IF EXISTS (
                    SELECT [NormalizedEmail]
                    FROM [Users]
                    GROUP BY [NormalizedEmail]
                    HAVING COUNT(*) > 1
                )
                BEGIN
                    THROW 51001, 'Duplicate normalized emails exist in Users. Resolve duplicates before applying EnforceGlobalUniqueUserEmail; see docs/operations/auth-duplicate-email-remediation.md.', 1;
                END
                """);

            migrationBuilder.CreateIndex(
                name: "IX_Users_NormalizedEmail",
                table: "Users",
                column: "NormalizedEmail",
                unique: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "IX_Users_NormalizedEmail",
                table: "Users");
        }
    }
}
