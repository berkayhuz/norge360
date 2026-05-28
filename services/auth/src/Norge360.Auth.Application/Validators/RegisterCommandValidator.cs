// <copyright file="RegisterCommandValidator.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using FluentValidation;
using Microsoft.Extensions.Options;
using Norge360.Auth.Application.Features.Commands;
using Norge360.Auth.Application.Options;
using Norge360.Localization;

namespace Norge360.Auth.Application.Validators;

public sealed partial class RegisterCommandValidator : AbstractValidator<RegisterCommand>
{
    public RegisterCommandValidator(IOptions<PasswordPolicyOptions> passwordPolicyOptions)
    {
        var policy = passwordPolicyOptions.Value;

        RuleFor(x => x.TenantName).NotEmpty().MinimumLength(2).MaximumLength(200);
        RuleFor(x => x.UserName).NotEmpty().MinimumLength(3).MaximumLength(64);
        RuleFor(x => x.Email).NotEmpty().EmailAddress().MaximumLength(256);
        RuleFor(x => x.Password)
            .ApplyPasswordPolicy(policy);
        RuleFor(x => x.Culture)
            .MaximumLength(20)
            .Must(value => string.IsNullOrWhiteSpace(value) || Norge360Cultures.IsSupportedCulture(value))
            .WithMessage($"Culture must be one of: {string.Join(", ", Norge360Cultures.SupportedCultureNames)}.");
    }
}
