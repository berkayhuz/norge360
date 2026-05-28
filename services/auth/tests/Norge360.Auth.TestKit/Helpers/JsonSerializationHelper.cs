// <copyright file="JsonSerializationHelper.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using System.Text.Json;

namespace Norge360.Auth.TestKit.Helpers;

public static class JsonSerializationHelper
{
    public static readonly JsonSerializerOptions WebOptions = new(JsonSerializerDefaults.Web)
    {
        PropertyNameCaseInsensitive = true
    };

    public static StringContent ToJsonContent<T>(T value) =>
        new(JsonSerializer.Serialize(value, WebOptions), System.Text.Encoding.UTF8, "application/json");

    public static async Task<T?> ReadAsJsonAsync<T>(HttpContent content)
    {
        var payload = await content.ReadAsStringAsync();
        return JsonSerializer.Deserialize<T>(payload, WebOptions);
    }
}

