// <copyright file="HttpTenantContextAccessorTests.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using FluentAssertions;
using Microsoft.AspNetCore.Http;
using Norge360.Auth.API.Accessors;
using Norge360.Auth.Application.Records;

namespace Norge360.Auth.Api.FunctionalTests.Security;

public sealed class HttpTenantContextAccessorTests
{
    [Fact]
    public void Current_Should_Be_Null_When_HttpContext_Is_Null()
    {
        var accessor = new HttpContextAccessor { HttpContext = null };
        var sut = new HttpTenantContextAccessor(accessor);

        sut.Current.Should().BeNull();
    }

    [Fact]
    public void Current_Should_Return_TenantContext_From_HttpContext_Items()
    {
        var context = new DefaultHttpContext();
        var tenantContext = new TenantContext(Guid.NewGuid(), "acme", "header", true);
        context.Items["TenantContext"] = tenantContext;

        var sut = new HttpTenantContextAccessor(new HttpContextAccessor { HttpContext = context });

        sut.Current.Should().Be(tenantContext);
    }

    [Fact]
    public void Current_Should_Be_Null_When_TenantContext_Item_Is_Missing()
    {
        var context = new DefaultHttpContext();
        var sut = new HttpTenantContextAccessor(new HttpContextAccessor { HttpContext = context });

        sut.Current.Should().BeNull();
    }
}
