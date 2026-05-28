// <copyright file="AccountSecurityCommandValidators.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using FluentValidation;
using Norge360.Auth.Application.Features.Commands;

namespace Norge360.Auth.Application.Validators;

public sealed class GetAccountSecuritySummaryQueryValidator : AbstractValidator<GetAccountSecuritySummaryQuery>
{
    public GetAccountSecuritySummaryQueryValidator()
    {
        RuleFor(x => x.TenantId).NotEmpty();
        RuleFor(x => x.UserId).NotEmpty();
    }
}

public sealed class GetMfaStatusQueryValidator : AbstractValidator<GetMfaStatusQuery>
{
    public GetMfaStatusQueryValidator()
    {
        RuleFor(x => x.TenantId).NotEmpty();
        RuleFor(x => x.UserId).NotEmpty();
    }
}

public sealed class SetupMfaCommandValidator : AbstractValidator<SetupMfaCommand>
{
    public SetupMfaCommandValidator()
    {
        RuleFor(x => x.TenantId).NotEmpty();
        RuleFor(x => x.UserId).NotEmpty();
        RuleFor(x => x.Issuer).NotEmpty().MaximumLength(100);
    }
}

public sealed class ConfirmMfaCommandValidator : AbstractValidator<ConfirmMfaCommand>
{
    public ConfirmMfaCommandValidator()
    {
        RuleFor(x => x.TenantId).NotEmpty();
        RuleFor(x => x.UserId).NotEmpty();
        RuleFor(x => x.VerificationCode).NotEmpty().Matches("^[0-9]{6}$");
    }
}

public sealed class DisableMfaCommandValidator : AbstractValidator<DisableMfaCommand>
{
    public DisableMfaCommandValidator()
    {
        RuleFor(x => x.TenantId).NotEmpty();
        RuleFor(x => x.UserId).NotEmpty();
        RuleFor(x => x.VerificationCode).NotEmpty().Matches("^[0-9]{6}$");
    }
}

public sealed class RegenerateRecoveryCodesCommandValidator : AbstractValidator<RegenerateRecoveryCodesCommand>
{
    public RegenerateRecoveryCodesCommandValidator()
    {
        RuleFor(x => x.TenantId).NotEmpty();
        RuleFor(x => x.UserId).NotEmpty();
    }
}

public sealed class ListTrustedDevicesQueryValidator : AbstractValidator<ListTrustedDevicesQuery>
{
    public ListTrustedDevicesQueryValidator()
    {
        RuleFor(x => x.TenantId).NotEmpty();
        RuleFor(x => x.UserId).NotEmpty();
    }
}

public sealed class RevokeTrustedDeviceCommandValidator : AbstractValidator<RevokeTrustedDeviceCommand>
{
    public RevokeTrustedDeviceCommandValidator()
    {
        RuleFor(x => x.TenantId).NotEmpty();
        RuleFor(x => x.UserId).NotEmpty();
        RuleFor(x => x.DeviceId).NotEmpty();
    }
}

public sealed class ConfirmEmailChangeForAccountCommandValidator : AbstractValidator<ConfirmEmailChangeForAccountCommand>
{
    public ConfirmEmailChangeForAccountCommandValidator()
    {
        RuleFor(x => x.TenantId).NotEmpty();
        RuleFor(x => x.UserId).NotEmpty();
        RuleFor(x => x.Token).NotEmpty().MaximumLength(512);
    }
}
