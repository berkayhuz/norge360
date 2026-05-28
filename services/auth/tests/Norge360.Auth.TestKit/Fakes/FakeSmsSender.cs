// <copyright file="FakeSmsSender.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

namespace Norge360.Auth.TestKit.Fakes;

public sealed class FakeSmsSender
{
    private readonly List<SmsEnvelope> _messages = [];

    public IReadOnlyCollection<SmsEnvelope> Messages => _messages;

    public void Send(string phoneNumber, string message)
    {
        _messages.Add(new SmsEnvelope(phoneNumber, message));
    }

    public sealed record SmsEnvelope(string PhoneNumber, string Message);
}

