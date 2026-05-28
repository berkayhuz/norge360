// <copyright file="ApplicationValidatorsBenchmarks.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using BenchmarkDotNet.Attributes;
using Microsoft.Extensions.Options;
using Norge360.Auth.Application.Features.Commands;
using Norge360.Auth.Application.Options;
using Norge360.Auth.Application.Validators;

namespace Norge360.Auth.Benchmarks;

[MemoryDiagnoser]
public class ApplicationValidatorsBenchmarks
{
    private LoginCommandValidator _loginValidator = default!;
    private RegisterCommandValidator _registerValidator = default!;
    private RefreshTokenCommandValidator _refreshTokenValidator = default!;
    private LogoutCommandValidator _logoutValidator = default!;
    private ForgotPasswordCommandValidator _forgotPasswordValidator = default!;
    private ResetPasswordCommandValidator _resetPasswordValidator = default!;
    private ConfirmEmailCommandValidator _confirmEmailValidator = default!;
    private ResendEmailConfirmationCommandValidator _resendEmailConfirmationValidator = default!;
    private ChangePasswordCommandValidator _changePasswordValidator = default!;
    private ChangeEmailCommandValidator _changeEmailValidator = default!;
    private ConfirmEmailChangeCommandValidator _confirmEmailChangeValidator = default!;
    private GetUserProfileCommandValidator _getUserProfileValidator = default!;
    private UpdateProfileCommandValidator _updateProfileValidator = default!;

    private LoginCommand _loginCommand = default!;
    private RegisterCommand _registerCommand = default!;
    private RefreshTokenCommand _refreshTokenCommand = default!;
    private LogoutCommand _logoutCommand = default!;
    private ForgotPasswordCommand _forgotPasswordCommand = default!;
    private ResetPasswordCommand _resetPasswordCommand = default!;
    private ConfirmEmailCommand _confirmEmailCommand = default!;
    private ResendEmailConfirmationCommand _resendEmailConfirmationCommand = default!;
    private ChangePasswordCommand _changePasswordCommand = default!;
    private ChangeEmailCommand _changeEmailCommand = default!;
    private ConfirmEmailChangeCommand _confirmEmailChangeCommand = default!;
    private GetUserProfileCommand _getUserProfileCommand = default!;
    private UpdateProfileCommand _updateProfileCommand = default!;

    [GlobalSetup]
    public void Setup()
    {
        var policy = Options.Create(new PasswordPolicyOptions
        {
            MinimumLength = 12,
            MaxLength = 64,
            RequiredUniqueChars = 4,
            RequireUppercase = true,
            RequireLowercase = true,
            RequireDigit = true,
            RequireNonAlphanumeric = true,
            DisallowWhitespace = true,
            BlacklistedPasswords = []
        });

        _loginValidator = new LoginCommandValidator();
        _registerValidator = new RegisterCommandValidator(policy);
        _refreshTokenValidator = new RefreshTokenCommandValidator();
        _logoutValidator = new LogoutCommandValidator();
        _forgotPasswordValidator = new ForgotPasswordCommandValidator();
        _resetPasswordValidator = new ResetPasswordCommandValidator(policy);
        _confirmEmailValidator = new ConfirmEmailCommandValidator();
        _resendEmailConfirmationValidator = new ResendEmailConfirmationCommandValidator();
        _changePasswordValidator = new ChangePasswordCommandValidator(policy);
        _changeEmailValidator = new ChangeEmailCommandValidator();
        _confirmEmailChangeValidator = new ConfirmEmailChangeCommandValidator();
        _getUserProfileValidator = new GetUserProfileCommandValidator();
        _updateProfileValidator = new UpdateProfileCommandValidator();

        var tenantId = Guid.NewGuid();
        var userId = Guid.NewGuid();
        _loginCommand = new LoginCommand(tenantId, "tester@example.test", "Str0ng!Pass123", false, null, null, null, null);
        _registerCommand = new RegisterCommand("Acme", "tester", "tester@example.test", "Str0ng!Pass123", "Test", "User", "en-US", null, null);
        _refreshTokenCommand = new RefreshTokenCommand(tenantId, Guid.NewGuid(), "refresh-token", null, null);
        _logoutCommand = new LogoutCommand(tenantId, Guid.NewGuid(), "refresh-token");
        _forgotPasswordCommand = new ForgotPasswordCommand(tenantId, "tester@example.test", null, null, null, null);
        _resetPasswordCommand = new ResetPasswordCommand(tenantId, userId, "token", "Str0ng!Pass123", null, null, null, null);
        _confirmEmailCommand = new ConfirmEmailCommand(tenantId, userId, "token", null, null, null, null);
        _resendEmailConfirmationCommand = new ResendEmailConfirmationCommand(tenantId, "tester@example.test", null, null, null, null);
        _changePasswordCommand = new ChangePasswordCommand(tenantId, userId, "Old!Pass123", "Str0ng!Pass123", true, null, null, null, null, null);
        _changeEmailCommand = new ChangeEmailCommand(tenantId, userId, "new@example.test", "old@example.test", "Str0ng!Pass123", null, null, null, null);
        _confirmEmailChangeCommand = new ConfirmEmailChangeCommand(tenantId, userId, "new@example.test", "token", null, null, null, null);
        _getUserProfileCommand = new GetUserProfileCommand(tenantId, userId);
        _updateProfileCommand = new UpdateProfileCommand(tenantId, userId, "Test", "User");
    }

    [Benchmark] public object Validate_LoginCommand() => _loginValidator.Validate(_loginCommand);
    [Benchmark] public object Validate_RegisterCommand() => _registerValidator.Validate(_registerCommand);
    [Benchmark] public object Validate_RefreshTokenCommand() => _refreshTokenValidator.Validate(_refreshTokenCommand);
    [Benchmark] public object Validate_LogoutCommand() => _logoutValidator.Validate(_logoutCommand);
    [Benchmark] public object Validate_ForgotPasswordCommand() => _forgotPasswordValidator.Validate(_forgotPasswordCommand);
    [Benchmark] public object Validate_ResetPasswordCommand() => _resetPasswordValidator.Validate(_resetPasswordCommand);
    [Benchmark] public object Validate_ConfirmEmailCommand() => _confirmEmailValidator.Validate(_confirmEmailCommand);
    [Benchmark] public object Validate_ResendEmailConfirmationCommand() => _resendEmailConfirmationValidator.Validate(_resendEmailConfirmationCommand);
    [Benchmark] public object Validate_ChangePasswordCommand() => _changePasswordValidator.Validate(_changePasswordCommand);
    [Benchmark] public object Validate_ChangeEmailCommand() => _changeEmailValidator.Validate(_changeEmailCommand);
    [Benchmark] public object Validate_ConfirmEmailChangeCommand() => _confirmEmailChangeValidator.Validate(_confirmEmailChangeCommand);
    [Benchmark] public object Validate_GetUserProfileCommand() => _getUserProfileValidator.Validate(_getUserProfileCommand);
    [Benchmark] public object Validate_UpdateProfileCommand() => _updateProfileValidator.Validate(_updateProfileCommand);
}

