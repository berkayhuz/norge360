// <copyright file="ApplicationPrimitivesBenchmarks.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using BenchmarkDotNet.Attributes;
using Norge360.Auth.Application.Descriptors;
using Norge360.Auth.Application.Options;
using Norge360.Auth.Application.Records;

namespace Norge360.Auth.Benchmarks;

[MemoryDiagnoser]
public class ApplicationPrimitivesBenchmarks
{
    private readonly Guid _tenantId = Guid.NewGuid();
    private readonly Guid _userId = Guid.NewGuid();
    private readonly Guid _sessionId = Guid.NewGuid();
    private InvitationDeliveryOptions _invitationOptions = default!;
    private AuthAuditRecord _auditRecordA = default!;
    private AuthAuditRecord _auditRecordB = default!;
    private SecurityAlert _securityAlertA = default!;
    private SecurityAlert _securityAlertB = default!;
    private TenantContext _tenantContextA = default!;
    private TenantContext _tenantContextB = default!;

    [GlobalSetup]
    public void Setup()
    {
        _invitationOptions = new InvitationDeliveryOptions
        {
            AcceptBaseUrl = "https://app.norge360.test/",
            AcceptPath = "invite/accept"
        };

        _auditRecordA = new AuthAuditRecord(_tenantId, "login", "success", _userId, _sessionId, "tester@example.test", "10.0.0.1", "Chrome", "c1", "t1");
        _auditRecordB = _auditRecordA with { Outcome = "failed" };

        _securityAlertA = new SecurityAlert("auth", "warning", "multiple failed login", _tenantId, _userId, _sessionId, "c1", "t1");
        _securityAlertB = _securityAlertA with { Severity = "critical" };

        _tenantContextA = new TenantContext(_tenantId, "acme", "header", true);
        _tenantContextB = new TenantContext(_tenantId, "acme", "header", true);
    }

    [Benchmark] public AccessTokenDescriptor Create_AccessTokenDescriptor() => new("access-token", DateTime.UtcNow.AddMinutes(15));
    [Benchmark] public RefreshTokenDescriptor Create_RefreshTokenDescriptor() => new("refresh-token", "hash", DateTime.UtcNow.AddDays(7));
    [Benchmark] public AuthAuditRecord Create_AuthAuditRecord() => new(_tenantId, "password_change", "success", _userId, _sessionId, "tester@example.test", "10.0.0.1", "Chrome", "c1", "t1", "{}");
    [Benchmark] public SecurityAlert Create_SecurityAlert() => new("mfa", "info", "mfa enabled", _tenantId, _userId, _sessionId, "c1", "t1", "{}");
    [Benchmark] public TenantContext Create_TenantContext() => new(_tenantId, "acme", "header", true);
    [Benchmark] public string InvitationDelivery_BuildAcceptUrl() => _invitationOptions.BuildAcceptUrl(_tenantId, "token-123", "user@example.test");
    [Benchmark] public bool AuthAuditRecord_Equals() => _auditRecordA.Equals(_auditRecordB);
    [Benchmark] public int AuthAuditRecord_HashCode() => _auditRecordA.GetHashCode();
    [Benchmark] public AuthAuditRecord AuthAuditRecord_WithClone() => _auditRecordA with { Metadata = "{\"k\":\"v\"}" };
    [Benchmark] public bool SecurityAlert_Equals() => _securityAlertA.Equals(_securityAlertB);
    [Benchmark] public int SecurityAlert_HashCode() => _securityAlertA.GetHashCode();
    [Benchmark] public SecurityAlert SecurityAlert_WithClone() => _securityAlertA with { Metadata = "{\"reason\":\"threshold\"}" };
    [Benchmark] public bool TenantContext_Equals() => _tenantContextA.Equals(_tenantContextB);
    [Benchmark] public int TenantContext_HashCode() => _tenantContextA.GetHashCode();
}
