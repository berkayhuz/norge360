// <copyright file="InvitationCommandValidators.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using FluentValidation;
using Microsoft.Extensions.Options;
using Norge360.Auth.Application.Features.Commands;
using Norge360.Auth.Application.Options;

namespace Norge360.Auth.Application.Validators;

public sealed class CreateTenantInvitationCommandValidator : AbstractValidator<CreateTenantInvitationCommand>
{
    public CreateTenantInvitationCommandValidator()
    {
        RuleFor(x => x.TenantId).NotEmpty();
        RuleFor(x => x.InvitedByUserId).NotEmpty();
        RuleFor(x => x.Email).NotEmpty().EmailAddress().MaximumLength(256);
        RuleFor(x => x.FirstName).MaximumLength(100);
        RuleFor(x => x.LastName).MaximumLength(100);
    }
}

public sealed class AcceptTenantInvitationCommandValidator : AbstractValidator<AcceptTenantInvitationCommand>
{
    public AcceptTenantInvitationCommandValidator(IOptions<PasswordPolicyOptions> passwordPolicyOptions)
    {
        var policy = passwordPolicyOptions.Value;

        RuleFor(x => x.TenantId).NotEmpty();
        RuleFor(x => x.Token).NotEmpty().MaximumLength(512);
        RuleFor(x => x.UserName).NotEmpty().MinimumLength(3).MaximumLength(64);
        RuleFor(x => x.Email).NotEmpty().EmailAddress().MaximumLength(256);
        RuleFor(x => x.Password).ApplyPasswordPolicy(policy);
        RuleFor(x => x.FirstName).MaximumLength(100);
        RuleFor(x => x.LastName).MaximumLength(100);
    }
}

public sealed class ListTenantInvitationsCommandValidator : AbstractValidator<ListTenantInvitationsCommand>
{
    public ListTenantInvitationsCommandValidator()
    {
        RuleFor(x => x.TenantId).NotEmpty();
        RuleFor(x => x.RequestedByUserId).NotEmpty();
    }
}

public sealed class ResendTenantInvitationCommandValidator : AbstractValidator<ResendTenantInvitationCommand>
{
    public ResendTenantInvitationCommandValidator()
    {
        RuleFor(x => x.TenantId).NotEmpty();
        RuleFor(x => x.InvitationId).NotEmpty();
        RuleFor(x => x.RequestedByUserId).NotEmpty();
    }
}

public sealed class RevokeTenantInvitationCommandValidator : AbstractValidator<RevokeTenantInvitationCommand>
{
    public RevokeTenantInvitationCommandValidator()
    {
        RuleFor(x => x.TenantId).NotEmpty();
        RuleFor(x => x.InvitationId).NotEmpty();
        RuleFor(x => x.RequestedByUserId).NotEmpty();
    }
}
