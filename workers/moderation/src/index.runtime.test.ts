import assert from "node:assert/strict";
import { afterEach, beforeEach, test } from "node:test";
import worker, { app } from "./index";

const supabaseURL = "https://example.supabase.co";
const userID = "11111111-1111-4111-8111-111111111111";
const groupID = "22222222-2222-4222-8222-222222222222";
const originalFetch = globalThis.fetch;

const env = {
    SUPABASE_URL: supabaseURL,
    SUPABASE_ANON_KEY: "placeholder",
    SUPABASE_SERVICE_ROLE_KEY: "placeholder"
};

function base64URL(value: string): string {
    return Buffer.from(value).toString("base64url");
}

function validToken(subject = userID): string {
    const header = base64URL(JSON.stringify({ alg: "HS256", typ: "JWT" }));
    const payload = base64URL(JSON.stringify({
        aud: "authenticated",
        exp: Math.floor(Date.now() / 1_000) + 3_600,
        iss: `${supabaseURL}/auth/v1`,
        sub: subject
    }));
    return `${header}.${payload}.test-signature`;
}

function response(value: unknown, status = 200): Response {
    return new Response(JSON.stringify(value), {
        status,
        headers: { "Content-Type": "application/json" }
    });
}

function mockSupabase(options: {
    authenticatedUserID?: string;
    authStatus?: number;
    roleRows?: unknown[];
    ownerRows?: unknown[];
} = {}): void {
    globalThis.fetch = async (input): Promise<Response> => {
        const url = String(input);
        if (url.includes("/auth/v1/user")) {
            if ((options.authStatus ?? 200) !== 200) return response({ error: "invalid_token" }, options.authStatus);
            return response({ user: { id: options.authenticatedUserID ?? userID } });
        }
        if (url.includes("/rest/v1/community_moderator_roles")) {
            return response(options.roleRows ?? []);
        }
        if (url.includes("/rest/v1/community_group_memberships")) {
            return response(options.ownerRows ?? []);
        }
        return response([]);
    };
}

async function request(path: string, token?: string, method = "GET"): Promise<Response> {
    const pending: Promise<unknown>[] = [];
    const requestHeaders = token ? { Authorization: `Bearer ${token}` } : undefined;
    const result = await worker.fetch(
        new Request(`https://worker.example${path}`, { method, headers: requestHeaders }),
        env,
        { waitUntil: (promise: Promise<unknown>) => pending.push(promise) } as unknown as ExecutionContext
    );
    await Promise.allSettled(pending);
    return result;
}

beforeEach(() => {
    mockSupabase();
});

afterEach(() => {
    globalThis.fetch = originalFetch;
});

test("health route is reachable through the runtime handler", async () => {
    const result = await request("/health");
    assert.equal(result.status, 200);
    assert.deepEqual(await result.json(), { status: "ok" });
});

test("account deletion rejects a missing bearer token", async () => {
    const result = await request("/account/delete", undefined, "POST");
    assert.equal(result.status, 401);
    assert.deepEqual(await result.json(), { error: "invalid_session" });
});

test("account deletion rejects a token revoked by Supabase Auth", async () => {
    mockSupabase({ authStatus: 401 });
    const result = await request("/account/delete", validToken(), "POST");
    assert.equal(result.status, 401);
    assert.deepEqual(await result.json(), { error: "invalid_session" });
});

test("moderator route requires a server-side moderator role", async () => {
    mockSupabase({ roleRows: [] });
    const result = await request("/v1/me", validToken());
    assert.equal(result.status, 403);
    assert.deepEqual(await result.json(), { error: "moderator_role_required" });
});

test("moderator role is returned only after runtime auth and role checks", async () => {
    mockSupabase({ roleRows: [{ role: "reviewer" }] });
    const result = await request("/v1/me", validToken());
    assert.equal(result.status, 200);
    assert.deepEqual(await result.json(), { role: "reviewer" });
});

test("account deletion blocks group owners before creating a deletion job", async () => {
    mockSupabase({ ownerRows: [{ group_id: groupID }] });
    const result = await request("/account/delete", validToken(), "POST");
    assert.equal(result.status, 409);
    assert.deepEqual(await result.json(), { error: "group_ownership_transfer_required" });
});

assert.equal(typeof app.fetch, "function");
