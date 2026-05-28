// <copyright file="AccountLifecycleCommandValidators.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using FluentValidation;
using Microsoft.Extensions.Options;
using Norge360.Auth.Application.Features.Commands;
using Norge360.Auth.Application.Options;

namespace Norge360.Auth.Application.Validators;

public sealed class ForgotPasswordCommandValidator : AbstractValidator<ForgotPasswordCommand>
{
    public ForgotPasswordCommandValidator()
    {
        RuleFor(x => x.TenantId).NotEmpty();
        RuleFor(x => x.Email).NotEmpty().EmailAddress().MaximumLength(256);
    }
}

public sealed class ResetPasswordCommandValidator : AbstractValidator<ResetPasswordCommand>
{
    public ResetPasswordCommandValidator(IOptions<PasswordPolicyOptions> options)
    {
        RuleFor(x => x.TenantId).NotEmpty();
        RuleFor(x => x.UserId).NotEmpty();
        RuleFor(x => x.Token).NotEmpty().MaximumLength(512);
        RuleFor(x => x.NewPassword).ApplyPasswordPolicy(options.Value);
    }
}

public sealed class ConfirmEmailCommandValidator : AbstractValidator<ConfirmEmailCommand>
{
    public ConfirmEmailCommandValidator()
    {
        RuleFor(x => x.TenantId).NotEmpty();
        RuleFor(x => x.UserId).NotEmpty();
        RuleFor(x => x.Token).NotEmpty().MaximumLength(512);
    }
}

public sealed class ResendEmailConfirmationCommandValidator : AbstractValidator<ResendEmailConfirmationCommand>
{
    public ResendEmailConfirmationCommandValidator()
    {
        RuleFor(x => x.TenantId).NotEmpty();
        RuleFor(x => x.Email).NotEmpty().EmailAddress().MaximumLength(256);
    }
}

public sealed class ChangePasswordCommandValidator : AbstractValidator<ChangePasswordCommand>
{
    public ChangePasswordCommandValidator(IOptions<PasswordPolicyOptions> options)
    {
        RuleFor(x => x.TenantId).NotEmpty();
        RuleFor(x => x.UserId).NotEmpty();
        RuleFor(x => x.CurrentPassword).NotEmpty().MaximumLength(256);
        RuleFor(x => x.NewPassword).ApplyPasswordPolicy(options.Value);
    }
}

public sealed class ChangeEmailCommandValidator : AbstractValidator<ChangeEmailCommand>
{
    public ChangeEmailCommandValidator()
    {
        RuleFor(x => x.TenantId).NotEmpty();
        RuleFor(x => x.UserId).NotEmpty();
        RuleFor(x => x.NewEmail).NotEmpty().EmailAddress().MaximumLength(256);
        RuleFor(x => x.CurrentEmail).NotEmpty().EmailAddress().MaximumLength(256);
        RuleFor(x => x.CurrentPassword).MaximumLength(256);
    }
}

public sealed class ConfirmEmailChangeCommandValidator : AbstractValidator<ConfirmEmailChangeCommand>
{
    public ConfirmEmailChangeCommandValidator()
    {
        RuleFor(x => x.TenantId).NotEmpty();
        RuleFor(x => x.UserId).NotEmpty();
        RuleFor(x => x.NewEmail).NotEmpty().EmailAddress().MaximumLength(256);
        RuleFor(x => x.Token).NotEmpty().MaximumLength(512);
    }
}

public sealed class GetUserProfileCommandValidator : AbstractValidator<GetUserProfileCommand>
{
    public GetUserProfileCommandValidator()
    {
        RuleFor(x => x.TenantId).NotEmpty();
        RuleFor(x => x.UserId).NotEmpty();
    }
}

public sealed class UpdateProfileCommandValidator : AbstractValidator<UpdateProfileCommand>
{
    public UpdateProfileCommandValidator()
    {
        RuleFor(x => x.TenantId).NotEmpty();
        RuleFor(x => x.UserId).NotEmpty();
        RuleFor(x => x.FirstName).MaximumLength(100);
        RuleFor(x => x.LastName).MaximumLength(100);
    }
}

internal static class PasswordRuleBuilderExtensions
{
    public static IRuleBuilderOptions<T, string> ApplyPasswordPolicy<T>(
        this IRuleBuilder<T, string> ruleBuilder,
        PasswordPolicyOptions policy) =>
        ruleBuilder
            .NotEmpty()
            .MinimumLength(policy.MinimumLength)
            .MaximumLength(policy.MaxLength)
            .Must(password => !policy.DisallowWhitespace || password.All(c => !char.IsWhiteSpace(c))).WithMessage("Password cannot contain whitespace.")
            .Must(password => !policy.RequireUppercase || password.Any(char.IsUpper)).WithMessage("Password must contain at least one uppercase letter.")
            .Must(password => !policy.RequireLowercase || password.Any(char.IsLower)).WithMessage("Password must contain at least one lowercase letter.")
            .Must(password => !policy.RequireDigit || password.Any(char.IsDigit)).WithMessage("Password must contain at least one digit.")
            .Must(password => !policy.RequireNonAlphanumeric || password.Any(ch => !char.IsLetterOrDigit(ch))).WithMessage("Password must contain at least one non-alphanumeric character.")
            .Must(password => password.Distinct().Count() >= policy.RequiredUniqueChars).WithMessage($"Password must contain at least {policy.RequiredUniqueChars} unique characters.")
            .Must(password => !policy.BlacklistedPasswords.Contains(password, StringComparer.OrdinalIgnoreCase)).WithMessage("Password is not allowed.");
}
