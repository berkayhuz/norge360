// <copyright file="RoleManagementCommandValidators.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using FluentValidation;
using Norge360.Auth.Application.Features.Commands;

namespace Norge360.Auth.Application.Validators;

public sealed class ListTenantMembersCommandValidator : AbstractValidator<ListTenantMembersCommand>
{
    public ListTenantMembersCommandValidator()
    {
        RuleFor(x => x.TenantId).NotEmpty();
        RuleFor(x => x.RequestedByUserId).NotEmpty();
    }
}

public sealed class UpdateTenantMemberRolesCommandValidator : AbstractValidator<UpdateTenantMemberRolesCommand>
{
    public UpdateTenantMemberRolesCommandValidator()
    {
        RuleFor(x => x.TenantId).NotEmpty();
        RuleFor(x => x.TargetUserId).NotEmpty();
        RuleFor(x => x.RequestedByUserId).NotEmpty();
        RuleFor(x => x.Roles).Must(x => x is { Count: > 0 }).WithMessage("At least one role is required.");
        RuleForEach(x => x.Roles)
            .NotEmpty()
            .MaximumLength(128);
    }
}

public sealed class ListRoleCatalogCommandValidator : AbstractValidator<ListRoleCatalogCommand>
{
    public ListRoleCatalogCommandValidator()
    {
        RuleFor(x => x.TenantId).NotEmpty();
        RuleFor(x => x.RequestedByUserId).NotEmpty();
    }
}
