// <copyright file="LoginCommandValidator.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using FluentValidation;
using Norge360.Auth.Application.Features.Commands;

namespace Norge360.Auth.Application.Validators;

public sealed class LoginCommandValidator : AbstractValidator<LoginCommand>
{
    public LoginCommandValidator()
    {
        RuleFor(x => x.EmailOrUserName).NotEmpty().MaximumLength(256);
        RuleFor(x => x.Password).NotEmpty().MaximumLength(256);
        RuleFor(x => x.MfaCode).MaximumLength(32);
        RuleFor(x => x.RecoveryCode).MaximumLength(128);
    }
}
