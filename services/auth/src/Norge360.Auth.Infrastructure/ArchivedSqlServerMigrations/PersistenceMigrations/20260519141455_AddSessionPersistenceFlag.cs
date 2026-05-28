using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Norge360.Auth.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class AddSessionPersistenceFlag : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<bool>(
                name: "IsPersistent",
                table: "UserSessions",
                type: "bit",
                nullable: false,
                defaultValue: false);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "IsPersistent",
                table: "UserSessions");
        }
    }
}
