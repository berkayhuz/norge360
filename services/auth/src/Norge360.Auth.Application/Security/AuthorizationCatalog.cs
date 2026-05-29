// <copyright file="AuthorizationCatalog.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using Norge360.Auth.Domain.Entities;

namespace Norge360.Auth.Application.Security;

public static class AuthorizationCatalog
{
    public const string WildcardPermission = "*";

    public static class Roles
    {
        public const string PlatformOwner = "platform-owner";
        public const string PlatformAdmin = "platform-admin";
        public const string PlatformUser = "user";
    }

    public static class Permissions
    {
        public const string SessionSelf = "session:self";
        public const string ProfileSelf = "profile:self";
        public const string UsersInvite = "users.invite";
        public const string UsersManage = "users.manage";
        public const string RolesRead = "roles.read";
        public const string RolesManage = "roles.manage";
        public const string PlatformManage = "platform.manage";
        public const string AuditRead = "audit.read";
        public const string AccountRead = "account.read";
        public const string CustomersRead = "customers.read";
        public const string CustomersWrite = "customers.write";
        public const string CustomersDelete = "customers.delete";
        public const string CustomersManage = "customers.manage";
        public const string ContactsRead = "contacts.read";
        public const string ContactsManage = "contacts.manage";
        public const string ContactsSensitiveRead = "contacts.sensitive.read";
        public const string ContactsInternalNotesRead = "contacts.internal-notes.read";
        public const string CompaniesRead = "companies.read";
        public const string CompaniesManage = "companies.manage";
        public const string CompaniesSensitiveRead = "companies.sensitive.read";
        public const string CompaniesFinancialRead = "companies.financial.read";
        public const string CompaniesInternalNotesRead = "companies.internal-notes.read";
        public const string LeadsRead = "leads.read";
        public const string LeadsManage = "leads.manage";
        public const string LeadsSensitiveRead = "leads.sensitive.read";
        public const string LeadsFinancialRead = "leads.financial.read";
        public const string LeadsInternalNotesRead = "leads.internal-notes.read";
        public const string OpportunitiesRead = "opportunities.read";
        public const string OpportunitiesManage = "opportunities.manage";
        public const string OpportunitiesFinancialRead = "opportunities.financial.read";
        public const string OpportunitiesInternalNotesRead = "opportunities.internal-notes.read";
        public const string DealsRead = "deals.read";
        public const string DealsManage = "deals.manage";
        public const string DealsFinancialRead = "deals.financial.read";
        public const string DealsInternalNotesRead = "deals.internal-notes.read";
        public const string QuotesRead = "quotes.read";
        public const string QuotesManage = "quotes.manage";
        public const string QuotesFinancialRead = "quotes.financial.read";
        public const string QuotesInternalNotesRead = "quotes.internal-notes.read";
        public const string TicketsRead = "tickets.read";
        public const string TicketsManage = "tickets.manage";
        public const string TicketsInternalNotesRead = "tickets.internal-notes.read";
        public const string DocumentsRead = "documents.read";
        public const string DocumentsManage = "documents.manage";
        public const string DocumentsPreviewRead = "documents.preview.read";
    }

    private static readonly RoleDefinition[] RoleDefinitions =
    [
        new(Roles.PlatformOwner, 100, true, [WildcardPermission]),
        new(Roles.PlatformAdmin, 80, false,
        [
            Permissions.UsersInvite,
            Permissions.UsersManage,
            Permissions.RolesRead,
            Permissions.RolesManage,
            Permissions.PlatformManage,
            Permissions.AuditRead,
            Permissions.AccountRead,
            Permissions.CustomersRead,
            Permissions.CustomersWrite,
            Permissions.CustomersManage,
            Permissions.ContactsRead,
            Permissions.ContactsManage,
            Permissions.ContactsSensitiveRead,
            Permissions.ContactsInternalNotesRead,
            Permissions.CompaniesRead,
            Permissions.CompaniesManage,
            Permissions.CompaniesSensitiveRead,
            Permissions.CompaniesFinancialRead,
            Permissions.CompaniesInternalNotesRead,
            Permissions.LeadsRead,
            Permissions.LeadsManage,
            Permissions.LeadsSensitiveRead,
            Permissions.LeadsFinancialRead,
            Permissions.LeadsInternalNotesRead,
            Permissions.OpportunitiesRead,
            Permissions.OpportunitiesManage,
            Permissions.OpportunitiesFinancialRead,
            Permissions.OpportunitiesInternalNotesRead,
            Permissions.DealsRead,
            Permissions.DealsManage,
            Permissions.DealsFinancialRead,
            Permissions.DealsInternalNotesRead,
            Permissions.QuotesRead,
            Permissions.QuotesManage,
            Permissions.QuotesFinancialRead,
            Permissions.QuotesInternalNotesRead,
            Permissions.TicketsRead,
            Permissions.TicketsManage,
            Permissions.TicketsInternalNotesRead,
            Permissions.DocumentsRead,
            Permissions.DocumentsManage,
            Permissions.DocumentsPreviewRead,
            "crm.customer-management.companies.read",
            "crm.customer-management.companies.manage",
            "crm.customer-management.contacts.read",
            "crm.customer-management.contacts.manage",
            "crm.customer-management.customers.read",
            "crm.customer-management.customers.manage",
            "analytics.read",
            "artificial-intelligence.read",
            "artificial-intelligence.manage",
            "marketing.campaigns.read",
            "marketing.campaigns.manage",
            "calendar-sync.read",
            "calendar-sync.manage",
            "catalog.products.read",
            "catalog.products.manage",
            "contracts.read",
            "contracts.manage",
            "customer-intelligence.duplicates.read",
            "customer-intelligence.duplicates.manage",
            "customer-intelligence.health.read",
            "customer-intelligence.search.read",
            "customer-intelligence.timeline.read",
            "documents.approvals.manage",
            "documents.versions.manage",
            "finance.operations.read",
            "finance.operations.manage",
            "integrations.read",
            "integrations.manage",
            "crm.settings.read",
            "crm.settings.manage",
            "crm.integrations.read",
            "crm.integrations.manage",
            "crm.apiKeys.read",
            "crm.apiKeys.manage",
            "crm.webhooks.read",
            "crm.webhooks.manage",
            "crm.inbox.read",
            "crm.inbox.reply",
            "crm.inbox.convert",
            "knowledge-base.articles.read",
            "knowledge-base.articles.manage",
            "knowledge-base.categories.read",
            "knowledge-base.categories.manage",
            "lead-scores.read",
            "opportunity.quotes.read",
            "opportunity.quotes.manage",
            "orders.read",
            "orders.manage",
            "omnichannel.read",
            "omnichannel.manage",
            "proposals.read",
            "proposals.manage",
            "sales-forecasts.read",
            "sales-forecasts.manage",
            "support-inbox.connections.read",
            "support-inbox.connections.manage",
            "support-inbox.rules.read",
            "support-inbox.messages.read",
            "tags.read",
            "tags.manage",
            "tags.groups.manage",
            "tags.smart-labels.manage",
            "tags.classifications.manage",
            "ticket.assignments.read",
            "ticket.categories.read",
            "ticket.queues.read",
            "ticket.queues.manage",
            "ticket.sla-policies.read",
            "ticket.sla-policies.manage",
            "ticket.status-history.read",
            "win-loss.read",
            "win-loss.manage",
            "workflow.approvals.manage",
            "workflow.assignment-rules.manage",
            "workflow.rules.manage",
            "workflow.webhooks.manage",
            "work-management.read",
            "work-management.manage",
            "pipeline.lost-reasons.manage",
            "pipeline.lost-reasons.read",
            "pipeline.opportunities.manage",
            "pipeline.stage-history.read",
            "pipeline.lead-conversions.manage",
            "pipeline.lead-conversions.read",
            Permissions.SessionSelf,
            Permissions.ProfileSelf
        ]),
        new(Roles.PlatformUser, 10, false,
        [
            Permissions.SessionSelf,
            Permissions.ProfileSelf
        ])
    ];

    public static IReadOnlyCollection<RoleDefinition> RolesCatalog => RoleDefinitions;

    public static IReadOnlyCollection<string> PermissionCatalog =>
        RoleDefinitions.SelectMany(x => x.Permissions)
            .Concat([WildcardPermission])
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .OrderBy(value => value, StringComparer.OrdinalIgnoreCase)
            .ToArray();

    public static RoleDefinition? FindRole(string role) =>
        RoleDefinitions.FirstOrDefault(x => string.Equals(x.Name, role, StringComparison.OrdinalIgnoreCase));

    public static bool IsKnownRole(string role) => FindRole(role) is not null;

    public static int HighestRoleRank(IEnumerable<string> roles) =>
        roles.Select(role => FindRole(role)?.Rank ?? 0).DefaultIfEmpty(0).Max();

    public static bool HasRole(User user, string role) =>
        user.GetRoles().Contains(role, StringComparer.OrdinalIgnoreCase);

    public static bool HasPermission(User user, string permission) =>
        user.GetPermissions().Contains(WildcardPermission, StringComparer.OrdinalIgnoreCase) ||
        user.GetPermissions().Contains(permission, StringComparer.OrdinalIgnoreCase);

    public static IReadOnlyCollection<string> ResolvePermissions(IEnumerable<string> roles, IEnumerable<string>? explicitPermissions = null)
    {
        var values = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var role in roles)
        {
            var definition = FindRole(role);
            if (definition is null)
            {
                continue;
            }

            foreach (var permission in definition.Permissions)
            {
                values.Add(permission);
            }
        }

        foreach (var permission in explicitPermissions ?? [])
        {
            if (!string.IsNullOrWhiteSpace(permission))
            {
                values.Add(permission.Trim());
            }
        }

        return values.OrderBy(value => value, StringComparer.OrdinalIgnoreCase).ToArray();
    }

    public static string Serialize(IEnumerable<string> values) =>
        string.Join(',', values.Where(value => !string.IsNullOrWhiteSpace(value)).Select(value => value.Trim()).Distinct(StringComparer.OrdinalIgnoreCase));
}

public sealed record RoleDefinition(string Name, int Rank, bool IsProtected, IReadOnlyCollection<string> Permissions);
