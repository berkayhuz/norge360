// <copyright file="AuthCommandValidatorTests.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using FluentAssertions;
using Microsoft.Extensions.Options;
using Norge360.Auth.Application.Features.Commands;
using Norge360.Auth.Application.Options;
using Norge360.Auth.Application.Validators;
using OptionsFactory = Microsoft.Extensions.Options.Options;

namespace Norge360.Auth.Application.UnitTests.Security;

public sealed class AuthCommandValidatorTests
{
    [Fact]
    public void LoginCommandValidator_When_TenantIdIsEmpty_Should_AcceptTenantlessLogin()
    {
        var validator = new LoginCommandValidator();
        var command = new LoginCommand(
            Guid.Empty,
            "ada@example.com",
            "Str0ng!Pass123",
            false,
            null,
            null,
            null,
            null);

        var result = validator.Validate(command);

        result.IsValid.Should().BeTrue();
    }

    [Fact]
    public void LoginCommandValidator_When_CredentialsAreBlank_Should_Reject()
    {
        var validator = new LoginCommandValidator();
        var command = new LoginCommand(Guid.Empty, string.Empty, string.Empty, false, null, null, null, null);

        var result = validator.Validate(command);

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(error => error.PropertyName == nameof(LoginCommand.EmailOrUserName));
        result.Errors.Should().Contain(error => error.PropertyName == nameof(LoginCommand.Password));
        result.Errors.Should().NotContain(error => error.PropertyName == nameof(LoginCommand.TenantId));
    }

    [Fact]
    public void CreateWorkspaceCommandValidator_When_NameIsInvalid_Should_Reject()
    {
        var validator = new CreateWorkspaceCommandValidator();
        var command = new CreateWorkspaceCommand(Guid.NewGuid(), Guid.NewGuid(), " ", null, null, null, null, null);

        var result = validator.Validate(command);

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(error => error.PropertyName == nameof(CreateWorkspaceCommand.Name));
    }

    [Fact]
    public void SwitchWorkspaceCommandValidator_When_TargetTenantIdIsEmpty_Should_Reject()
    {
        var validator = new SwitchWorkspaceCommandValidator();
        var command = new SwitchWorkspaceCommand(Guid.NewGuid(), Guid.Empty, Guid.NewGuid(), null, null, null, null);

        var result = validator.Validate(command);

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(error => error.PropertyName == nameof(SwitchWorkspaceCommand.TargetTenantId));
    }

    [Fact]
    public void DeleteWorkspaceCommandValidator_When_TargetTenantIdIsEmpty_Should_Reject()
    {
        var validator = new DeleteWorkspaceCommandValidator();
        var command = new DeleteWorkspaceCommand(Guid.NewGuid(), Guid.Empty, Guid.NewGuid(), null, null, null, null);

        var result = validator.Validate(command);

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(error => error.PropertyName == nameof(DeleteWorkspaceCommand.TargetTenantId));
    }

    [Fact]
    public void UpdateTenantMemberRolesCommandValidator_When_RolesAreEmpty_Should_Reject()
    {
        var validator = new UpdateTenantMemberRolesCommandValidator();
        var command = new UpdateTenantMemberRolesCommand(Guid.NewGuid(), Guid.NewGuid(), Guid.NewGuid(), [], null, null, null, null);

        var result = validator.Validate(command);

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(error => error.PropertyName == nameof(UpdateTenantMemberRolesCommand.Roles));
    }

    [Fact]
    public void UpdateTenantMemberRolesCommandValidator_When_RoleValueIsBlank_Should_Reject()
    {
        var validator = new UpdateTenantMemberRolesCommandValidator();
        var command = new UpdateTenantMemberRolesCommand(Guid.NewGuid(), Guid.NewGuid(), Guid.NewGuid(), ["tenant-user", " "], null, null, null, null);

        var result = validator.Validate(command);

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(error => error.PropertyName == "Roles[1]");
    }

    [Fact]
    public void RevokeSessionCommandValidator_When_SessionIdIsEmpty_Should_Reject()
    {
        var validator = new RevokeSessionCommandValidator();
        var command = new RevokeSessionCommand(Guid.NewGuid(), Guid.NewGuid(), Guid.NewGuid(), Guid.Empty, "alice@example.com", null, null, null, null);

        var result = validator.Validate(command);

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(error => error.PropertyName == nameof(RevokeSessionCommand.SessionId));
    }

    [Fact]
    public void RevokeOtherSessionsCommandValidator_When_EmailIsInvalid_Should_Reject()
    {
        var validator = new RevokeOtherSessionsCommandValidator();
        var command = new RevokeOtherSessionsCommand(Guid.NewGuid(), Guid.NewGuid(), Guid.NewGuid(), "not-an-email", null, null, null, null);

        var result = validator.Validate(command);

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(error => error.PropertyName == nameof(RevokeOtherSessionsCommand.Email));
    }

    [Fact]
    public void ChangeEmailCommandValidator_When_CurrentEmailIsInvalid_Should_Reject()
    {
        var validator = new ChangeEmailCommandValidator();
        var command = new ChangeEmailCommand(Guid.NewGuid(), Guid.NewGuid(), "new@example.com", "not-an-email", null, null, null, null, null);

        var result = validator.Validate(command);

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(error => error.PropertyName == nameof(ChangeEmailCommand.CurrentEmail));
    }

    [Fact]
    public void ResetPasswordCommandValidator_When_TokenIsMissing_Should_Reject()
    {
        var validator = new ResetPasswordCommandValidator(OptionsFactory.Create(new PasswordPolicyOptions()));
        var command = new ResetPasswordCommand(Guid.NewGuid(), Guid.NewGuid(), string.Empty, "Str0ng!Pass123", null, null, null, null);

        var result = validator.Validate(command);

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(error => error.PropertyName == nameof(ResetPasswordCommand.Token));
    }

    [Fact]
    public async Task RegisterCommandValidator_When_RequestIsValid_Should_Accept()
    {
        var validator = new RegisterCommandValidator(OptionsFactory.Create(new PasswordPolicyOptions()));

        var result = await validator.ValidateAsync(new RegisterCommand(
            "Acme",
            "ada",
            "ada@example.com",
            "Str0ng!Pass123",
            "Ada",
            "Lovelace",
            "en-US",
            null,
            null));

        result.IsValid.Should().BeTrue();
    }

    [Fact]
    public async Task RegisterCommandValidator_When_PasswordHasWhitespace_Should_Reject()
    {
        var validator = new RegisterCommandValidator(OptionsFactory.Create(new PasswordPolicyOptions()));

        var result = await validator.ValidateAsync(new RegisterCommand(
            "Acme",
            "grace",
            "Grace@Example.com",
            "Str0ng! Pass123",
            "Grace",
            "Hopper",
            "en-US",
            null,
            null));

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(error =>
            error.PropertyName == nameof(RegisterCommand.Password) &&
            error.ErrorMessage == "Password cannot contain whitespace.");
    }
}
