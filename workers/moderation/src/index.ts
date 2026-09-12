import { createClient } from "@supabase/supabase-js";
import { Hono, type Context } from "hono";

type Variables = {
  requestID: string;
  moderatorID: string;
  moderatorRole: ModeratorRoleRow["role"];
};

type ModeratorRoleRow = {
  role: "reviewer" | "moderator" | "admin";
};

type AuthenticatedSupabaseUser = {
  id: string;
};

type ReportResolution = "no_action" | "needs_investigation" | "member_contacted" | "escalated";
type ReviewStatus = "resolved" | "dismissed";
type EnforcementAction = "remove_content" | "restore_content" | "restrict_author" | "revoke_author_restriction";

type PushSignalTable = "community_notifications" | "community_message_signals" | "community_group_chat_signals";
type PushWebhookTable = PushSignalTable | "community_group_chat_push_fanout_jobs";

type LogLevel = "info" | "warn" | "error";
type LogField = string | number | boolean | null | undefined;
type LogFields = Record<string, LogField>;

function structuredLog(level: LogLevel, operation: string, fields: LogFields = {}): void {
  const entry = {
    timestamp: new Date().toISOString(),
    service: "norge360-moderation",
    level,
    operation,
    ...fields
  };
  const line = JSON.stringify(entry);
  if (level === "error") {
    console.error(line);
  } else if (level === "warn") {
    console.warn(line);
  } else {
    console.log(line);
  }
}

const allowedResolutions = new Set<ReportResolution>([
  "no_action",
  "needs_investigation",
  "member_contacted",
  "escalated"
]);
const allowedStatuses = new Set<ReviewStatus>(["resolved", "dismissed"]);
const allowedEnforcementActions = new Set<EnforcementAction>([
  "remove_content",
  "restore_content",
  "restrict_author",
  "revoke_author_restriction"
]);

type CommunityNotificationWebhookPayload = {
  type?: string;
  table?: PushWebhookTable;
  schema?: string;
  record?: {
    id?: string;
    recipient_id?: string;
    type?: string;
  };
};

type GroupChatUploadRequest = {
  groupID?: string;
  mimeType?: string;
  byteSize?: number;
};

type CommunityMediaScanMessage = {
  version: 1;
  mediaType: "group" | "direct";
  attachmentID: string;
};

type CommunityMediaScanClaim = {
  provider_asset_id: string;
  attempt_count: number;
  terminal: boolean;
};

type CommunityMediaScanQueueResult = {
  provider_asset_id: string;
  queue_state: "queued" | "already_queued" | "already_processed";
};

type CommunityMediaScanStatus = {
  outcome: "pending_scan" | "passed" | "needs_review" | "rejected" | "unavailable";
};

type CommunityMediaCleanupMessage = {
  version: 1;
  kind: "media_cleanup";
  mediaType: "group" | "direct";
  attachmentID: string;
  providerAssetID: string | null;
};

type CommunityMediaCleanupRow = {
  attachment_id: string;
  provider_asset_id: string | null;
};

type CommunityPushDeliveryMessage = {
  version: 1;
  kind: "push_delivery";
  sourceTable: PushSignalTable;
  eventID: string;
};

type CommunityGroupChatFanoutMessage = {
  version: 1;
  kind: "group_chat_fanout";
  jobID: string;
};

type CommunityPushQueueMessage = CommunityPushDeliveryMessage | CommunityGroupChatFanoutMessage;
type CommunityQueueMessage =
  | CommunityMediaScanMessage
  | CommunityMediaCleanupMessage
  | CommunityPushDeliveryMessage
  | CommunityGroupChatFanoutMessage;

const communityMediaScanMaxAttempts = 5;
const communityMediaScanRetryDelaySeconds = 60;
const communityMediaCleanupBatchSize = 50;
const communityMediaCleanupDispatchRounds = 4;
const communityMediaCleanupRetryDelaySeconds = 60;
const communityPushDeliveryRetryDelaySeconds = 30;
const communityPushDeliveryLeaseSeconds = 120;

type DirectMessageImageUploadRequest = {
  conversationID?: string;
  mimeType?: string;
  byteSize?: number;
};

type PushDevice = {
  id: string;
  token: string;
  environment: "development" | "production";
};

type APNsDeliveryResult = {
  deviceID: string;
  status: number;
  outcome: "delivered" | "invalid_device" | "retry" | "failed";
  errorCode: string | null;
};

type APNsTokenCache = {
  token: string;
  expiresAt: number;
};

type CloudflareImagesSigningKeyCache = {
  key: string;
  cryptoKey: CryptoKey;
  expiresAt: number;
};

type CloudflareImageDeliveryCache = {
  deliveryURL: string;
  expiresAt: number;
};

type PrivateMediaViewCache = {
  url: string;
  expiresAt: number;
};

type MediaViewType = "group" | "direct";

type MediaViewAuthorization = {
  provider_asset_id: string | null;
  rate_limited: boolean;
};

type PrivateMediaViewResult =
  | { status: "ok"; url: string }
  | { status: "not_found" }
  | { status: "rate_limited" }
  | { status: "unavailable" };

type ProfileMediaCleanupRow = {
  id: string;
  bucket_id: "avatars" | "profile-media";
  storage_path: string;
  attempts: number;
};

// Workers may reuse a single isolate. This bounded cache avoids signing a new
// APNs JWT for each notification without making authorization state durable.
let apnsTokenCache: APNsTokenCache | undefined;
let cloudflareImagesSigningKeyCache: CloudflareImagesSigningKeyCache | undefined;

// These caches are deliberately bounded and keyed by the authenticated viewer
// plus attachment. A cached URL never outlives the five-minute provider token;
// the shorter local TTL reduces repeated authorization/provider work without
// extending access after an already-issued token would expire.
const privateMediaViewURLCache = new Map<string, PrivateMediaViewCache>();
const privateMediaViewInFlight = new Map<string, Promise<PrivateMediaViewResult>>();
const cloudflareImageDeliveryCache = new Map<string, CloudflareImageDeliveryCache>();
const cloudflareImageDeliveryInFlight = new Map<string, Promise<string | null>>();

const privateMediaViewCacheTTLSeconds = 30;
const privateMediaViewCacheMaxEntries = 256;
const cloudflareImageDeliveryCacheTTLSeconds = 10 * 60;
const cloudflareImageDeliveryCacheMaxEntries = 256;
const providerRequestTimeoutMilliseconds = 10_000;
const providerSafeRetryAttempts = 3;

const app = new Hono<{ Bindings: Env; Variables: Variables }>();

app.use("*", async (context, next) => {
  const suppliedRequestID = context.req.header("X-Request-ID");
  const requestID = suppliedRequestID && isUUID(suppliedRequestID)
    ? suppliedRequestID
    : crypto.randomUUID();
  const startedAt = performance.now();
  context.set("requestID", requestID);

  try {
    await next();
  } finally {
    const status = context.res.status;
    context.header("X-Request-ID", requestID);
    structuredLog("info", "http_request", {
      request_id: requestID,
      method: context.req.method,
      route: context.req.path,
      status,
      duration_ms: Math.round(performance.now() - startedAt),
      outcome: status >= 500 ? "error" : "success",
      retry_count: 0
    });
  }
});

app.onError((error, context) => {
  const requestID = context.get("requestID") || crypto.randomUUID();
  context.header("X-Request-ID", requestID);
  structuredLog("error", "request_error", {
    request_id: requestID,
    method: context.req.method,
    route: context.req.path,
    error_type: error instanceof Error ? error.name : "unknown_error"
  });
  return context.json({ error: "internal_server_error", request_id: requestID }, 500);
});

app.get("/health", (context) => context.json({ status: "ok" }));

// This member-authenticated endpoint only stages a media object. It does not
// make it readable or attach it to a message; a future review/scan step does.
// The Cloudflare Images token stays in this Worker. The app receives only a
// short-lived, one-time direct-upload URL.
app.post("/media/group-chat/upload-url", async (context) => {
  const userID = await authenticatedUserID(context);
  if (!userID) return context.json({ error: "invalid_session" }, 401);

  const body = await context.req.json<GroupChatUploadRequest>().catch(() => null);
  const mimeType = body?.mimeType;
  const byteSize = body?.byteSize;
  const allowedMIMETypes = new Set(["image/jpeg", "image/png", "image/heic", "image/webp"]);
  if (!body || !body.groupID || !isUUID(body.groupID) || !mimeType || !allowedMIMETypes.has(mimeType) ||
      !Number.isInteger(byteSize) || byteSize === undefined || byteSize < 1 || byteSize > 10_485_760) {
    return context.json({ error: "invalid_media_request" }, 400);
  }
  // UUID text is case-insensitive, but the database's group-scoped opaque
  // path check compares text. Normalize once at the trust boundary so iOS
  // UUID serialization cannot create a false authorization failure.
  const groupID = body.groupID.toLowerCase();

  const serviceClient = createServiceClient(context.env);
  const [{ data: membership, error: membershipError }, { data: ban, error: banError }] = await Promise.all([
    serviceClient.from("community_group_memberships").select("group_id").eq("group_id", groupID).eq("user_id", userID).maybeSingle(),
    serviceClient.from("community_group_bans").select("group_id").eq("group_id", groupID).eq("user_id", userID).maybeSingle()
  ]);
  if (membershipError || banError) {
    structuredLog("error", "group_media_authorization_lookup_failed", {
      request_id: context.get("requestID"),
      error_code: membershipError?.code ?? banError?.code
    });
    return context.json({ error: "media_unavailable" }, 503);
  }
  if (!membership || ban) return context.json({ error: "media_unavailable" }, 403);

  // A direct-upload URL is a billable, abuse-prone capability. Keep this
  // deliberately tighter than normal chat-message creation.
  const { count: recentUploadCount, error: rateLimitError } = await serviceClient
    .from("community_group_chat_attachments")
    .select("id", { count: "exact", head: true })
    .eq("uploader_id", userID)
    .gte("created_at", new Date(Date.now() - 60_000).toISOString());
  if (rateLimitError) {
    structuredLog("error", "group_media_rate_limit_lookup_failed", {
      request_id: context.get("requestID"),
      error_code: rateLimitError.code
    });
    return context.json({ error: "media_unavailable" }, 503);
  }
  if ((recentUploadCount ?? 0) >= 6) return context.json({ error: "media_rate_limited" }, 429);

  const attachmentID = crypto.randomUUID();
  // Kept as an opaque, group-scoped legacy reference. The asset itself lives
  // in Cloudflare Images; clients never receive this path or a public URL.
  const storageReference = `${groupID}/${userID}/${attachmentID}`;

  const { error: attachmentError } = await serviceClient
    .from("community_group_chat_attachments")
    .insert({
      id: attachmentID,
      group_id: groupID,
      uploader_id: userID,
      storage_path: storageReference,
      mime_type: mimeType,
      byte_size: byteSize,
      status: "pending_upload",
      storage_provider: "cloudflare_images"
    });
  if (attachmentError) {
    // Intentionally log only the database constraint diagnostic, never the
    // opaque path, image payload, user input, or authentication material.
    structuredLog("error", "group_media_attachment_staging_failed", {
      request_id: context.get("requestID"),
      error_code: attachmentError.code
    });
    return context.json({ error: "media_unavailable" }, 503);
  }

  const upload = await createCloudflareImageUpload(context.env, {
    attachmentID,
    groupID,
    uploaderID: userID
  });
  if (!upload) {
    await serviceClient.from("community_group_chat_attachments").delete().eq("id", attachmentID);
    return context.json({ error: "media_unavailable" }, 503);
  }

  const { error: providerIDError } = await serviceClient
    .from("community_group_chat_attachments")
    .update({ provider_asset_id: upload.imageID })
    .eq("id", attachmentID);
  if (providerIDError) {
    // The image remains private and never becomes visible, but delete it to
    // avoid orphaned billable storage when database persistence fails.
    await deleteCloudflareImage(context.env, upload.imageID);
    await serviceClient.from("community_group_chat_attachments").delete().eq("id", attachmentID);
    structuredLog("error", "group_media_provider_identifier_persistence_failed", {
      request_id: context.get("requestID"),
      error_code: providerIDError.code
    });
    return context.json({ error: "media_unavailable" }, 503);
  }

  return context.json({ attachmentID, signedURL: upload.uploadURL }, 201);
});

// Called after the one-time direct upload finishes. The Worker atomically
// stages an authorized background scan and returns before provider download or
// Google Vision work begins. This is deliberately not a visibility/approval
// endpoint.
app.post("/media/group-chat/:attachmentID/upload-complete", async (context) => {
  const userID = await authenticatedUserID(context);
  if (!userID) return context.json({ error: "invalid_session" }, 401);

  const attachmentID = context.req.param("attachmentID");
  if (!isUUID(attachmentID)) return context.json({ error: "invalid_media_request" }, 400);
  return enqueueCommunityMediaScan(context, "group", attachmentID, userID);
});

app.get("/media/group-chat/:attachmentID/scan-status", async (context) => {
  const userID = await authenticatedUserID(context);
  if (!userID) return context.json({ error: "invalid_session" }, 401);
  const attachmentID = context.req.param("attachmentID");
  if (!isUUID(attachmentID)) return context.json({ error: "media_unavailable" }, 404);
  return mediaScanStatusResponse(context, "group", attachmentID, userID);
});

// A member receives a short-lived Images URL only after the Worker verifies
// membership, the active chat message, and the automated safety result.
app.get("/media/group-chat/:attachmentID/view-url", async (context) => {
  const userID = await authenticatedUserID(context);
  if (!userID) return context.json({ error: "invalid_session" }, 401);
  const attachmentID = context.req.param("attachmentID");
  if (!isUUID(attachmentID)) return context.json({ error: "media_unavailable" }, 404);
  return mediaViewResponse(
    context,
    await issuePrivateMediaViewURL(context.env, "group", attachmentID, userID)
  );
});

app.delete("/media/group-chat/:attachmentID", async (context) => {
  const userID = await authenticatedUserID(context);
  if (!userID) return context.json({ error: "invalid_session" }, 401);
  const attachmentID = context.req.param("attachmentID");
  if (!isUUID(attachmentID)) return context.json({ error: "media_unavailable" }, 404);
  const serviceClient = createServiceClient(context.env);
  const { data: attachment, error } = await serviceClient
    .from("community_group_chat_attachments")
    .select("id, group_id, uploader_id, message_id, provider_asset_id, status")
    .eq("id", attachmentID)
    .maybeSingle<{ id: string; group_id: string; uploader_id: string; message_id: string | null; provider_asset_id: string | null; status: string }>();
  if (error) {
    structuredLog("error", "group_media_cancellation_lookup_failed", {
      request_id: context.get("requestID"),
      error_code: error.code
    });
    return context.json({ error: "media_unavailable" }, 503);
  }
  if (!attachment || attachment.uploader_id !== userID || attachment.message_id || attachment.status === "deleted") {
    return context.json({ error: "media_unavailable" }, 404);
  }
  const [{ data: membership }, { data: ban }] = await Promise.all([
    serviceClient.from("community_group_memberships").select("group_id").eq("group_id", attachment.group_id).eq("user_id", userID).maybeSingle(),
    serviceClient.from("community_group_bans").select("group_id").eq("group_id", attachment.group_id).eq("user_id", userID).maybeSingle()
  ]);
  if (!membership || ban) return context.json({ error: "media_unavailable" }, 403);
  const { data: claimed, error: claimError } = await serviceClient
    .from("community_group_chat_attachments")
    .update({ status: "deleted", deleted_at: new Date().toISOString() })
    .eq("id", attachment.id).eq("uploader_id", userID).is("message_id", null)
    .in("status", ["pending_upload", "pending_scan", "pending_review", "ready", "rejected"])
    .select("id").maybeSingle();
  if (claimError) {
    structuredLog("error", "group_media_cancellation_claim_failed", {
      request_id: context.get("requestID"),
      error_code: claimError.code
    });
    return context.json({ error: "media_unavailable" }, 503);
  }
  if (!claimed) return context.json({ error: "media_unavailable" }, 409);
  if (attachment.provider_asset_id) await deleteCloudflareImage(context.env, attachment.provider_asset_id);
  const { error: deleteError } = await serviceClient.from("community_group_chat_attachments")
    .delete().eq("id", attachment.id).eq("status", "deleted").is("message_id", null);
  if (deleteError) {
    structuredLog("error", "group_media_cancellation_cleanup_failed", {
      request_id: context.get("requestID"),
      error_code: deleteError.code
    });
    return context.json({ error: "media_unavailable" }, 503);
  }
  return context.body(null, 204);
});

// Direct-message images use the same private, scan-before-delivery policy as
// group media. The conversation must already be active; a media upload never
// creates or bypasses a message request.
app.post("/media/direct-chat/upload-url", async (context) => {
  const userID = await authenticatedUserID(context);
  if (!userID) return context.json({ error: "invalid_session" }, 401);
  const body = await context.req.json<DirectMessageImageUploadRequest>().catch(() => null);
  const allowedMIMETypes = new Set(["image/jpeg", "image/png", "image/heic", "image/webp"]);
  if (!body?.conversationID || !isUUID(body.conversationID) || !body.mimeType || !allowedMIMETypes.has(body.mimeType) ||
      !Number.isInteger(body.byteSize) || body.byteSize === undefined || body.byteSize < 1 || body.byteSize > 10_485_760) {
    return context.json({ error: "invalid_media_request" }, 400);
  }
  const conversationID = body.conversationID.toLowerCase();
  const serviceClient = createServiceClient(context.env);
  const conversation = await activeDirectConversationForMember(serviceClient, conversationID, userID);
  if (!conversation) return context.json({ error: "media_unavailable" }, 403);

  const { count, error: rateLimitError } = await serviceClient
    .from("community_direct_message_attachments")
    .select("id", { count: "exact", head: true })
    .eq("uploader_id", userID)
    .gte("created_at", new Date(Date.now() - 60_000).toISOString());
  if (rateLimitError) {
    structuredLog("error", "direct_media_rate_limit_lookup_failed", {
      request_id: context.get("requestID"),
      error_code: rateLimitError.code
    });
    return context.json({ error: "media_unavailable" }, 503);
  }
  if ((count ?? 0) >= 6) return context.json({ error: "media_rate_limited" }, 429);

  const attachmentID = crypto.randomUUID();
  const { error: insertError } = await serviceClient
    .from("community_direct_message_attachments")
    .insert({
      id: attachmentID,
      conversation_id: conversationID,
      uploader_id: userID,
      storage_reference: `${conversationID}/${userID}/${attachmentID}`,
      mime_type: body.mimeType,
      byte_size: body.byteSize,
      status: "pending_upload"
    });
  if (insertError) {
    structuredLog("error", "direct_media_attachment_staging_failed", {
      request_id: context.get("requestID"),
      error_code: insertError.code
    });
    return context.json({ error: "media_unavailable" }, 503);
  }

  const upload = await createCloudflareImageUpload(context.env, { attachmentID, groupID: conversationID, uploaderID: userID });
  if (!upload) {
    await serviceClient.from("community_direct_message_attachments").delete().eq("id", attachmentID);
    return context.json({ error: "media_unavailable" }, 503);
  }
  const { error: providerError } = await serviceClient
    .from("community_direct_message_attachments")
    .update({ provider_asset_id: upload.imageID })
    .eq("id", attachmentID)
    .eq("status", "pending_upload");
  if (providerError) {
    await deleteCloudflareImage(context.env, upload.imageID);
    await serviceClient.from("community_direct_message_attachments").delete().eq("id", attachmentID);
    structuredLog("error", "direct_media_provider_identifier_persistence_failed", {
      request_id: context.get("requestID"),
      error_code: providerError.code
    });
    return context.json({ error: "media_unavailable" }, 503);
  }
  return context.json({ attachmentID, signedURL: upload.uploadURL }, 201);
});

app.post("/media/direct-chat/:attachmentID/upload-complete", async (context) => {
  const userID = await authenticatedUserID(context);
  if (!userID) return context.json({ error: "invalid_session" }, 401);
  const attachmentID = context.req.param("attachmentID");
  if (!isUUID(attachmentID)) return context.json({ error: "invalid_media_request" }, 400);
  return enqueueCommunityMediaScan(context, "direct", attachmentID, userID);
});

app.get("/media/direct-chat/:attachmentID/scan-status", async (context) => {
  const userID = await authenticatedUserID(context);
  if (!userID) return context.json({ error: "invalid_session" }, 401);
  const attachmentID = context.req.param("attachmentID");
  if (!isUUID(attachmentID)) return context.json({ error: "media_unavailable" }, 404);
  return mediaScanStatusResponse(context, "direct", attachmentID, userID);
});

app.get("/media/direct-chat/:attachmentID/view-url", async (context) => {
  const userID = await authenticatedUserID(context);
  if (!userID) return context.json({ error: "invalid_session" }, 401);
  const attachmentID = context.req.param("attachmentID");
  if (!isUUID(attachmentID)) return context.json({ error: "media_unavailable" }, 404);
  return mediaViewResponse(
    context,
    await issuePrivateMediaViewURL(context.env, "direct", attachmentID, userID)
  );
});

// Cancelling a composer preview only removes an unattached object owned by the
// caller. Attached media follows message retention/moderation rules instead.
app.delete("/media/direct-chat/:attachmentID", async (context) => {
  const userID = await authenticatedUserID(context);
  if (!userID) return context.json({ error: "invalid_session" }, 401);
  const attachmentID = context.req.param("attachmentID");
  if (!isUUID(attachmentID)) return context.json({ error: "media_unavailable" }, 404);

  const serviceClient = createServiceClient(context.env);
  const { data: attachment, error } = await serviceClient
    .from("community_direct_message_attachments")
    .select("id, uploader_id, message_id, provider_asset_id, status")
    .eq("id", attachmentID)
    .maybeSingle<{ id: string; uploader_id: string; message_id: string | null; provider_asset_id: string | null; status: string }>();
  if (error) {
    structuredLog("error", "direct_media_cancellation_lookup_failed", {
      request_id: context.get("requestID"),
      error_code: error.code
    });
    return context.json({ error: "media_unavailable" }, 503);
  }
  if (!attachment || attachment.uploader_id !== userID || attachment.message_id || attachment.status === "deleted") {
    return context.json({ error: "media_unavailable" }, 404);
  }

  const { data: claimed, error: claimError } = await serviceClient
    .from("community_direct_message_attachments")
    .update({ status: "deleted", deleted_at: new Date().toISOString() })
    .eq("id", attachment.id)
    .eq("uploader_id", userID)
    .is("message_id", null)
    .in("status", ["pending_upload", "pending_scan", "pending_review", "ready", "rejected"])
    .select("id")
    .maybeSingle();
  if (claimError) {
    structuredLog("error", "direct_media_cancellation_claim_failed", {
      request_id: context.get("requestID"),
      error_code: claimError.code
    });
    return context.json({ error: "media_unavailable" }, 503);
  }
  if (!claimed) return context.json({ error: "media_unavailable" }, 409);
  if (attachment.provider_asset_id) await deleteCloudflareImage(context.env, attachment.provider_asset_id);
  const { error: deleteError } = await serviceClient
    .from("community_direct_message_attachments")
    .delete()
    .eq("id", attachment.id)
    .eq("status", "deleted")
    .is("message_id", null);
  if (deleteError) {
    structuredLog("error", "direct_media_cancellation_cleanup_failed", {
      request_id: context.get("requestID"),
      error_code: deleteError.code
    });
    return context.json({ error: "media_unavailable" }, 503);
  }
  return context.body(null, 204);
});

// Message transport signals live outside the activity inbox and expire after
// 24 hours. Keep the existing webhook URL compatible during the database rollout.
// The webhook body is only a pointer; content and delivery eligibility are reloaded.
app.post("/internal/push/community-notification", async (context) => {
  const suppliedSecret = context.req.header("X-Norge360-Push-Secret");
  if (!await secretsMatch(suppliedSecret, context.env.PUSH_WEBHOOK_SECRET)) {
    return context.body(null, 401);
  }

  const payload = await context.req.json<CommunityNotificationWebhookPayload>().catch(() => null);
  const notificationID = payload?.record?.id;
  if (
    payload?.type !== "INSERT" ||
    !isPushWebhookTable(payload.table) ||
    payload.schema !== "public" ||
    !notificationID ||
    !isUUID(notificationID)
  ) {
    return context.body(null, 400);
  }

  try {
    if (payload.table === "community_group_chat_push_fanout_jobs") {
      await context.env.PUSH_DELIVERY_QUEUE.send({
        version: 1,
        kind: "group_chat_fanout",
        jobID: notificationID
      });
    } else {
      await context.env.PUSH_DELIVERY_QUEUE.send({
        version: 1,
        kind: "push_delivery",
        sourceTable: payload.table,
        eventID: notificationID
      });
    }
  } catch (error) {
    structuredLog("error", "push_delivery_queue_publish_failed", {
      request_id: context.get("requestID"),
      error_type: error instanceof Error ? error.name : "unknown_error"
    });
    return context.body(null, 503);
  }

  return context.body(null, 202);
});

app.use("/v1/*", async (context, next) => {
  const token = extractBearerToken(context);
  if (!token) {
    return context.json({ error: "authentication_required" }, 401);
  }

  const user = await authenticatedSupabaseUser(context, token);
  if (!user) {
    structuredLog("warn", "moderation_authentication_rejected", {
      request_id: context.get("requestID"),
      code: "invalid_token",
      status: 401
    });
    return context.json({ error: "invalid_session" }, 401);
  }

  const serviceClient = createClient(
    context.env.SUPABASE_URL,
    context.env.SUPABASE_SERVICE_ROLE_KEY,
    { auth: { autoRefreshToken: false, persistSession: false } }
  );
  const { data: role, error: roleError } = await serviceClient
    .from("community_moderator_roles")
    .select("role")
    .eq("user_id", user.id)
    .maybeSingle<ModeratorRoleRow>();

  if (roleError || !role) {
    structuredLog("warn", "moderation_role_lookup_denied", {
      request_id: context.get("requestID"),
      code: roleError?.code ?? "role_missing",
      status: 403
    });
    return context.json({ error: "moderator_role_required" }, 403);
  }

  context.set("moderatorID", user.id);
  context.set("moderatorRole", role.role);
  await next();
});

// This deliberately reveals only the authenticated staff member's own role.
// It lets native clients avoid exposing reviewer UI to regular members.
app.get("/v1/me", (context) => {
  return context.json({ role: context.get("moderatorRole") });
});

app.get("/v1/reports", async (context) => {
  const requestedStatus = context.req.query("status") ?? "open";
  const status = ["open", "resolved", "dismissed"].includes(requestedStatus) ? requestedStatus : "open";
  const requestedLimit = Number(context.req.query("limit") ?? "50");
  const limit = Number.isFinite(requestedLimit) ? Math.min(Math.max(Math.floor(requestedLimit), 1), 100) : 50;

  const serviceClient = createServiceClient(context.env);
  const { data, error } = await serviceClient
    .from("community_reports")
    .select("id, reporter_id, target_type, target_id, reason, details, created_at, review_status, resolution_action, resolution_note, reviewed_at, reviewed_by")
    .eq("review_status", status)
    .order("created_at", { ascending: false })
    .limit(limit);

  if (error) {
    structuredLog("error", "moderation_report_queue_failure", {
      request_id: context.get("requestID"),
      error_code: error.code
    });
    return context.json({ error: "report_queue_unavailable" }, 503);
  }
  return context.json({ reports: data });
});

app.get("/v1/reports/:reportID/context", async (context) => {
  const reportID = context.req.param("reportID");
  if (!isUUID(reportID)) return context.json({ error: "invalid_report_id" }, 400);

  const serviceClient = createServiceClient(context.env);
  const { data: report, error } = await serviceClient
    .from("community_reports")
    .select("id, reporter_id, target_type, target_id, reason, details, created_at, review_status, resolution_action, resolution_note, reviewed_at, reviewed_by")
    .eq("id", reportID)
    .maybeSingle<ReportRow>();
  if (error) {
    structuredLog("error", "moderation_report_context_failure", {
      request_id: context.get("requestID"),
      error_code: error.code
    });
    return context.json({ error: "report_context_unavailable" }, 503);
  }
  if (!report) return context.json({ error: "report_not_found" }, 404);

  const [target, actions] = await Promise.all([
    loadModerationTarget(serviceClient, report),
    serviceClient
      .from("community_moderation_action_audit")
      .select("id, action, subject_user_id, restriction_id, reverses_action_id, note, member_notice, created_at")
      .eq("report_id", report.id)
      .order("created_at", { ascending: false })
      .limit(50)
  ]);
  if (target.error || actions.error) {
    structuredLog("error", "moderation_report_context_dependency_failure", {
      request_id: context.get("requestID"),
      error_code: target.error?.code ?? actions.error?.code
    });
    return context.json({ error: "report_context_unavailable" }, 503);
  }
  return context.json({ report, target: target.data, actions: actions.data ?? [] });
});

app.post("/v1/reports/:reportID/resolve", async (context) => {
  const reportID = context.req.param("reportID");
  if (!isUUID(reportID)) {
    return context.json({ error: "invalid_report_id" }, 400);
  }

  const body = await context.req.json<{
    status?: string;
    action?: string;
    note?: string;
  }>().catch(() => null);
  if (!body || !allowedStatuses.has(body.status as ReviewStatus) || !allowedResolutions.has(body.action as ReportResolution)) {
    return context.json({ error: "invalid_resolution" }, 400);
  }
  const note = body.note?.trim() ?? null;
  if (note && note.length > 1_000) {
    return context.json({ error: "resolution_note_too_long" }, 400);
  }

  const { error } = await createServiceClient(context.env).rpc("resolve_community_report", {
    target_report_id: reportID,
    acting_moderator_id: context.get("moderatorID"),
    next_review_status: body.status,
    next_resolution_action: body.action,
    next_resolution_note: note
  });

  if (error) {
    // Do not expose report existence or internal policy details to a caller.
    structuredLog("error", "moderation_resolution_failure", {
      request_id: context.get("requestID"),
      error_code: error.code
    });
    return context.json({ error: "report_resolution_unavailable" }, 409);
  }
  return context.body(null, 204);
});

app.post("/v1/reports/:reportID/actions", async (context) => {
  if (context.get("moderatorRole") === "reviewer") {
    return context.json({ error: "moderator_role_required" }, 403);
  }
  const reportID = context.req.param("reportID");
  if (!isUUID(reportID)) return context.json({ error: "invalid_report_id" }, 400);

  const body = await context.req.json<{
    action?: string;
    note?: string;
    memberNotice?: string;
    restrictionHours?: number | null;
  }>().catch(() => null);
  if (!body || !allowedEnforcementActions.has(body.action as EnforcementAction)) {
    return context.json({ error: "invalid_moderation_action" }, 400);
  }
  const note = normalizedOptionalText(body.note, 1_000);
  const memberNotice = normalizedOptionalText(body.memberNotice, 500);
  const restrictionHours = body.restrictionHours === null || body.restrictionHours === undefined
    ? null
    : Number.isInteger(body.restrictionHours) && body.restrictionHours >= 1 && body.restrictionHours <= 8_760
      ? body.restrictionHours
      : undefined;
  if (note === undefined || memberNotice === undefined || restrictionHours === undefined) {
    return context.json({ error: "invalid_moderation_action" }, 400);
  }

  const serviceClient = createServiceClient(context.env);
  const { data: report, error: reportError } = await serviceClient
    .from("community_reports")
    .select("target_type")
    .eq("id", reportID)
    .maybeSingle<{ target_type: ReportRow["target_type"] }>();
  if (reportError || !report) {
    structuredLog("error", "moderation_action_report_lookup_failure", {
      request_id: context.get("requestID"),
      error_code: reportError?.code ?? "report_missing"
    });
    return context.json({ error: "moderation_action_unavailable" }, 409);
  }

  const actionRPC = report.target_type === "group_message"
    ? "apply_community_group_chat_moderation_action"
    : "apply_community_moderation_action";
  const { error } = await serviceClient.rpc(actionRPC, {
    target_report_id: reportID,
    acting_moderator_id: context.get("moderatorID"),
    requested_action: body.action,
    moderation_note: note,
    restriction_hours: restrictionHours,
    member_notice: memberNotice
  });
  if (error) {
    structuredLog("error", "moderation_enforcement_failure", {
      request_id: context.get("requestID"),
      error_code: error.code
    });
    return context.json({ error: "moderation_action_unavailable" }, 409);
  }
  return context.body(null, 204);
});

function createServiceClient(environment: Env) {
  return createClient(environment.SUPABASE_URL, environment.SUPABASE_SERVICE_ROLE_KEY, {
    auth: { autoRefreshToken: false, persistSession: false }
  });
}

async function enqueueCommunityMediaScan(
  context: Context<{ Bindings: Env; Variables: Variables }>,
  mediaType: "group" | "direct",
  attachmentID: string,
  uploaderID: string
): Promise<Response> {
  const { data: queueResult, error } = await createServiceClient(context.env)
    .rpc("queue_community_media_scan", {
      target_media_type: mediaType,
      target_attachment_id: attachmentID,
      target_uploader_id: uploaderID
    })
    .maybeSingle<CommunityMediaScanQueueResult>();

  if (error) {
    structuredLog("error", "community_media_scan_enqueue_lookup_failed", {
      request_id: context.get("requestID"),
      error_code: error.code
    });
    return context.json({ error: "media_unavailable" }, 503);
  }
  if (!queueResult) return context.json({ error: "media_unavailable" }, 403);
  if (queueResult.queue_state === "already_processed") {
    return context.json({ outcome: "pending_scan" }, 202);
  }

  try {
    await context.env.MEDIA_SCAN_QUEUE.send({
      version: 1,
      mediaType,
      attachmentID
    });
  } catch (error) {
    // The pending_scan row remains a durable outbox item. The scheduled
    // dispatcher will retry publishing it without making the client repeat
    // the upload or exposing provider details.
    structuredLog("error", "community_media_scan_queue_publish_failed", {
      request_id: context.get("requestID"),
      error_type: error instanceof Error ? error.name : "unknown_error"
    });
    return context.json({ error: "media_scan_unavailable" }, 503);
  }

  // Keep the existing iOS completion contract while making the work async;
  // clients use scan-status to wait for the terminal outcome.
  return context.json({ outcome: "pending_scan" }, 202);
}

async function mediaScanStatusResponse(
  context: Context<{ Bindings: Env; Variables: Variables }>,
  mediaType: "group" | "direct",
  attachmentID: string,
  viewerID: string
): Promise<Response> {
  const { data: status, error } = await createServiceClient(context.env)
    .rpc("get_community_media_scan_status", {
      target_media_type: mediaType,
      target_attachment_id: attachmentID,
      target_viewer_id: viewerID
    })
    .maybeSingle<CommunityMediaScanStatus>();
  if (error) {
    structuredLog("error", "community_media_scan_status_lookup_failed", {
      request_id: context.get("requestID"),
      error_code: error.code
    });
    return context.json({ error: "media_unavailable" }, 503);
  }
  if (!status) return context.json({ error: "media_unavailable" }, 404);
  return context.json(status);
}

function mediaViewResponse(
  context: Context<{ Bindings: Env; Variables: Variables }>,
  result: PrivateMediaViewResult
): Response {
  switch (result.status) {
    case "ok":
      return context.json({ url: result.url });
    case "rate_limited":
      return context.json({ error: "media_rate_limited" }, 429);
    case "not_found":
      return context.json({ error: "media_unavailable" }, 404);
    case "unavailable":
      return context.json({ error: "media_unavailable" }, 503);
  }
}

async function issuePrivateMediaViewURL(
  bindings: Env,
  mediaType: MediaViewType,
  attachmentID: string,
  userID: string
): Promise<PrivateMediaViewResult> {
  const cacheKey = `${mediaType}:${userID}:${attachmentID}`;
  const cached = readPrivateMediaViewCache(cacheKey);
  if (cached) return { status: "ok", url: cached };

  const existingRequest = privateMediaViewInFlight.get(cacheKey);
  if (existingRequest) return existingRequest;

  const request = (async (): Promise<PrivateMediaViewResult> => {
    const { data: authorization, error } = await createServiceClient(bindings)
      .rpc("issue_community_media_view", {
        target_media_type: mediaType,
        target_attachment_id: attachmentID,
        target_viewer_id: userID
      })
      .maybeSingle<MediaViewAuthorization>();

    if (error) {
      structuredLog("error", "private_media_view_authorization_failed", {
        error_code: error.code
      });
      return { status: "unavailable" };
    }
    if (!authorization) return { status: "not_found" };
    if (authorization.rate_limited) return { status: "rate_limited" };
    if (!authorization.provider_asset_id) return { status: "not_found" };

    try {
      const signedURL = await createCloudflareImageViewURL(bindings, authorization.provider_asset_id);
      if (!signedURL) return { status: "unavailable" };
      const url = signedURL.toString();
      writePrivateMediaViewCache(cacheKey, url);
      return { status: "ok", url };
    } catch (error) {
      structuredLog("error", "private_media_view_url_creation_failed", {
        error_type: error instanceof Error ? error.name : "unknown_error"
      });
      return { status: "unavailable" };
    }
  })();

  privateMediaViewInFlight.set(cacheKey, request);
  try {
    return await request;
  } finally {
    privateMediaViewInFlight.delete(cacheKey);
  }
}

function readPrivateMediaViewCache(cacheKey: string): string | null {
  const entry = privateMediaViewURLCache.get(cacheKey);
  if (!entry) return null;
  if (entry.expiresAt <= Date.now()) {
    privateMediaViewURLCache.delete(cacheKey);
    return null;
  }
  privateMediaViewURLCache.delete(cacheKey);
  privateMediaViewURLCache.set(cacheKey, entry);
  return entry.url;
}

function writePrivateMediaViewCache(cacheKey: string, url: string): void {
  if (privateMediaViewURLCache.has(cacheKey)) privateMediaViewURLCache.delete(cacheKey);
  while (privateMediaViewURLCache.size >= privateMediaViewCacheMaxEntries) {
    const oldestKey = privateMediaViewURLCache.keys().next().value;
    if (oldestKey === undefined) break;
    privateMediaViewURLCache.delete(oldestKey);
  }
  privateMediaViewURLCache.set(cacheKey, {
    url,
    expiresAt: Date.now() + (privateMediaViewCacheTTLSeconds * 1_000)
  });
}

type ActiveDirectConversation = {
  id: string;
  participant_one_id: string;
  participant_two_id: string;
};

// Service-role queries bypass RLS, so media endpoints repeat the essential
// active-member and block checks here. Do not replace this with client input
// or a simple conversation-ID existence check.
async function activeDirectConversationForMember(
  serviceClient: ReturnType<typeof createServiceClient>,
  conversationID: string,
  userID: string
): Promise<ActiveDirectConversation | null> {
  const { data: conversation, error } = await serviceClient
    .from("community_conversations")
    .select("id, participant_one_id, participant_two_id")
    .eq("id", conversationID)
    .eq("status", "active")
    .maybeSingle<ActiveDirectConversation>();
  if (error || !conversation || (conversation.participant_one_id !== userID && conversation.participant_two_id !== userID)) {
    return null;
  }

  const otherUserID = conversation.participant_one_id === userID
    ? conversation.participant_two_id
    : conversation.participant_one_id;
  const [{ data: callerMembership }, { data: otherMembership }, { data: block, error: blockError }] = await Promise.all([
    serviceClient.from("community_conversation_members").select("user_id").eq("conversation_id", conversationID).eq("user_id", userID).eq("status", "active").maybeSingle(),
    serviceClient.from("community_conversation_members").select("user_id").eq("conversation_id", conversationID).eq("user_id", otherUserID).eq("status", "active").maybeSingle(),
    serviceClient.from("user_blocks").select("blocker_id").or(`and(blocker_id.eq.${userID},blocked_user_id.eq.${otherUserID}),and(blocker_id.eq.${otherUserID},blocked_user_id.eq.${userID})`).maybeSingle()
  ]);
  if (!callerMembership || !otherMembership || blockError || block) return null;
  return conversation;
}

function extractBearerToken(context: Context<{ Bindings: Env; Variables: Variables }>): string | null {
  const authorization = context.req.header("Authorization");
  return authorization?.match(/^Bearer\s+([^\s]+)$/i)?.[1] ?? null;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function decodeBase64URL(value: string): string | null {
  const normalized = value.replace(/-/g, "+").replace(/_/g, "/");
  const remainder = normalized.length % 4;
  if (remainder === 1) return null;

  try {
    return atob(normalized.padEnd(normalized.length + ((4 - remainder) % 4), "="));
  } catch {
    return null;
  }
}

function expectedSupabaseAuthIssuer(supabaseURL: string): string | null {
  try {
    return `${new URL(supabaseURL).origin}/auth/v1`;
  } catch {
    return null;
  }
}

function hasValidSupabaseAccessTokenClaims(token: string, supabaseURL: string): boolean {
  const segments = token.split(".");
  if (segments.length !== 3 || segments.some((segment) => segment.length === 0)) return false;

  const payloadText = decodeBase64URL(segments[1]);
  if (!payloadText) return false;

  let payload: unknown;
  try {
    payload = JSON.parse(payloadText);
  } catch {
    return false;
  }
  if (!isRecord(payload)) return false;

  const expiry = payload.exp;
  if (typeof expiry !== "number" || !Number.isFinite(expiry) || expiry <= Math.floor(Date.now() / 1_000)) {
    return false;
  }

  const audience = typeof payload.aud === "string"
    ? [payload.aud]
    : Array.isArray(payload.aud)
      ? payload.aud.filter((value): value is string => typeof value === "string")
      : [];
  if (!audience.includes("authenticated")) return false;

  const issuer = expectedSupabaseAuthIssuer(supabaseURL);
  return issuer !== null && payload.iss === issuer && typeof payload.sub === "string" && isUUID(payload.sub);
}

async function authenticatedSupabaseUser(
  context: Context<{ Bindings: Env; Variables: Variables }>,
  token = extractBearerToken(context)
): Promise<AuthenticatedSupabaseUser | null> {
  if (!token || !hasValidSupabaseAccessTokenClaims(token, context.env.SUPABASE_URL)) return null;

  const client = createClient(context.env.SUPABASE_URL, context.env.SUPABASE_ANON_KEY, {
    auth: { autoRefreshToken: false, persistSession: false }
  });
  const { data, error } = await client.auth.getUser(token);
  // The local claim check is only an early policy gate. Supabase Auth remains
  // authoritative for signature verification, session validity, and revocation.
  return error || !data.user ? null : { id: data.user.id };
}

async function authenticatedUserID(context: Context<{ Bindings: Env; Variables: Variables }>): Promise<string | null> {
  const user = await authenticatedSupabaseUser(context);
  return user?.id ?? null;
}

async function secretsMatch(suppliedValue: string | undefined, expectedValue: string): Promise<boolean> {
  if (!suppliedValue || !expectedValue) return false;
  const encoder = new TextEncoder();
  const [suppliedDigest, expectedDigest] = await Promise.all([
    crypto.subtle.digest("SHA-256", encoder.encode(suppliedValue)),
    crypto.subtle.digest("SHA-256", encoder.encode(expectedValue))
  ]);
  const suppliedBytes = new Uint8Array(suppliedDigest);
  const expectedBytes = new Uint8Array(expectedDigest);
  let difference = 0;
  for (let index = 0; index < suppliedBytes.length; index += 1) {
    difference |= suppliedBytes[index] ^ expectedBytes[index];
  }
  return difference === 0;
}

async function createAPNsJWT(bindings: Env): Promise<string> {
  const now = Math.floor(Date.now() / 1_000);
  if (apnsTokenCache && apnsTokenCache.expiresAt > now) return apnsTokenCache.token;

  const keyID = bindings.APNS_KEY_ID.trim();
  const teamID = bindings.APNS_TEAM_ID.trim();
  if (!/^[A-Z0-9]{10}$/.test(keyID) || !/^[A-Z0-9]{10}$/.test(teamID)) {
    throw new Error("APNs signing configuration is invalid");
  }
  const header = base64URLEncode(JSON.stringify({ alg: "ES256", kid: keyID }));
  const claims = base64URLEncode(JSON.stringify({ iss: teamID, iat: now }));
  const signingInput = `${header}.${claims}`;
  const privateKey = await importAPNsPrivateKey(bindings.APNS_PRIVATE_KEY);
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    privateKey,
    new TextEncoder().encode(signingInput)
  );
  const token = `${signingInput}.${base64URLEncode(new Uint8Array(signature))}`;
  apnsTokenCache = { token, expiresAt: now + (45 * 60) };
  return token;
}

async function importAPNsPrivateKey(pem: string): Promise<CryptoKey> {
  const normalized = pem
    .replace(/-----BEGIN PRIVATE KEY-----/g, "")
    .replace(/-----END PRIVATE KEY-----/g, "")
    .replace(/\s/g, "");
  if (!normalized) throw new Error("APNs private key is missing");
  const bytes = Uint8Array.from(atob(normalized), (character) => character.charCodeAt(0));
  return crypto.subtle.importKey(
    "pkcs8",
    bytes,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"]
  );
}

function base64URLEncode(value: string | Uint8Array): string {
  const bytes = typeof value === "string" ? new TextEncoder().encode(value) : value;
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}

function providerRetryJitterMilliseconds(attempt: number): number {
  const random = new Uint32Array(1);
  crypto.getRandomValues(random);
  const jitter = Math.floor((random[0] / 0x1_0000_0000) * 100);
  return Math.min(2_000, (100 * (2 ** attempt)) + jitter);
}

function isRetryableProviderStatus(status: number): boolean {
  return status === 408 || status === 429 || status >= 500;
}

async function providerFetch(
  input: RequestInfo | URL,
  init: RequestInit = {}
): Promise<Response> {
  const method = (init.method ?? "GET").toString().toUpperCase();
  const retrySafe = method === "GET" || method === "HEAD" || method === "DELETE";
  const maxAttempts = retrySafe ? providerSafeRetryAttempts : 1;

  for (let attempt = 0; attempt < maxAttempts; attempt += 1) {
    let response: Response;
    try {
      response = await fetch(input, {
        ...init,
        signal: init.signal ?? AbortSignal.timeout(providerRequestTimeoutMilliseconds)
      });
    } catch (error) {
      if (!retrySafe || attempt === maxAttempts - 1) throw error;
      await new Promise<void>((resolve) => setTimeout(resolve, providerRetryJitterMilliseconds(attempt)));
      continue;
    }

    if (!retrySafe || attempt === maxAttempts - 1 || !isRetryableProviderStatus(response.status)) {
      return response;
    }

    await response.body?.cancel();
    await new Promise<void>((resolve) => setTimeout(resolve, providerRetryJitterMilliseconds(attempt)));
  }

  throw new Error("provider_request_failed");
}

async function sendAPNsMessage({
  device,
  notificationType,
  environment,
  jwt,
  bindings
}: {
  device: PushDevice;
  notificationType: string;
  environment: "development" | "production";
  jwt: string;
  bindings: Env;
}): Promise<APNsDeliveryResult> {
  const host = environment === "production" ? "api.push.apple.com" : "api.sandbox.push.apple.com";
  const body = notificationType === "message_request"
    ? "You have a new message request."
    : notificationType === "group_chat_message"
      ? "There is a new message in a group."
    : "You have a new message.";
  const response = await providerFetch(`https://${host}/3/device/${device.token}`, {
    method: "POST",
    headers: {
      authorization: `bearer ${jwt}`,
      "apns-topic": bindings.APNS_BUNDLE_ID,
      "apns-push-type": "alert",
      "apns-priority": "10",
      "content-type": "application/json"
    },
    body: JSON.stringify({
      aps: {
        alert: { title: "Norge360", body },
        sound: "default",
        "thread-id": "norge360-messages"
      },
      norge360: { notification_type: notificationType }
    })
  });
  const reason = response.ok ? null : await response.json<{ reason?: string }>().catch(() => null);
  const errorCode = reason?.reason ?? null;
  const invalidDevice = errorCode === "BadDeviceToken" ||
    errorCode === "DeviceTokenNotForTopic" ||
    errorCode === "Unregistered";
  return {
    deviceID: device.id,
    status: response.status,
    outcome: response.ok
      ? "delivered"
      : invalidDevice
        ? "invalid_device"
        : response.status === 408 || response.status === 429 || response.status >= 500
          ? "retry"
          : "failed",
    errorCode
  };
}

async function processCommunityPushDelivery(
  bindings: Env,
  message: CommunityPushDeliveryMessage
): Promise<void> {
  const serviceClient = createServiceClient(bindings);
  const { data: notification, error: notificationError } = await serviceClient
    .from(message.sourceTable)
    .select("id, recipient_id, type")
    .eq("id", message.eventID)
    .maybeSingle<{ id: string; recipient_id: string; type: string }>();
  if (notificationError) {
    structuredLog("error", "push_notification_lookup_failed", { error_code: notificationError.code });
    throw new Error("push_notification_lookup_failed");
  }
  if (!notification || !["message_request", "direct_message", "group_chat_message"].includes(notification.type)) {
    return;
  }

  if (message.sourceTable === "community_message_signals") {
    const { data: canDeliver, error: deliveryError } = await serviceClient
      .rpc("can_deliver_community_message_signal", { target_signal_id: message.eventID });
    if (deliveryError) {
      structuredLog("error", "push_eligibility_lookup_failed", { error_code: deliveryError.code });
      throw new Error("push_eligibility_lookup_failed");
    }
    if (canDeliver !== true) return;
  }
  if (message.sourceTable === "community_group_chat_signals") {
    const { data: canDeliver, error: deliveryError } = await serviceClient
      .rpc("can_deliver_community_group_chat_signal", { target_signal_id: message.eventID });
    if (deliveryError) {
      structuredLog("error", "group_chat_push_eligibility_lookup_failed", { error_code: deliveryError.code });
      throw new Error("group_chat_push_eligibility_lookup_failed");
    }
    if (canDeliver !== true) return;
  }

  const { data: preference, error: preferenceError } = await serviceClient
    .from("community_push_preferences")
    .select("message_push_enabled")
    .eq("user_id", notification.recipient_id)
    .maybeSingle<{ message_push_enabled: boolean }>();
  if (preferenceError) {
    structuredLog("error", "push_preference_lookup_failed", { error_code: preferenceError.code });
    throw new Error("push_preference_lookup_failed");
  }
  if (preference?.message_push_enabled === false) return;

  const { data: devices, error: devicesError } = await serviceClient
    .from("community_push_devices")
    .select("id, token, environment")
    .eq("user_id", notification.recipient_id)
    .eq("is_active", true)
    .returns<PushDevice[]>();
  if (devicesError) {
    structuredLog("error", "push_device_lookup_failed", { error_code: devicesError.code });
    throw new Error("push_device_lookup_failed");
  }
  if (!devices || devices.length === 0) return;

  const { data: claimedData, error: claimError } = await serviceClient
    .rpc("claim_community_push_deliveries", {
      target_source_table: message.sourceTable,
      target_event_id: message.eventID,
      target_device_ids: devices.map((device) => device.id),
      target_lease_seconds: communityPushDeliveryLeaseSeconds
    });
  if (claimError) {
    structuredLog("error", "push_delivery_claim_failed", { error_code: claimError.code });
    throw new Error("push_delivery_claim_failed");
  }

  const claimedRows = Array.isArray(claimedData)
    ? claimedData as Array<{ device_id: string }>
    : [];
  const claimedDeviceIDs = new Set((claimedRows ?? []).map((row) => row.device_id));
  const claimedDevices = devices.filter((device) => claimedDeviceIDs.has(device.id));
  if (claimedDevices.length === 0) return;

  let jwt: string;
  try {
    jwt = await createAPNsJWT(bindings);
  } catch (error) {
    const retryResults = claimedDevices.map((device) => ({
      event_id: message.eventID,
      device_id: device.id,
      outcome: "retry",
      apns_status: null,
      error_code: "apns_authentication_failed"
    }));
    const { error: finalizeError } = await serviceClient.rpc("finalize_community_push_deliveries", {
      target_deliveries: retryResults
    });
    if (finalizeError) {
      structuredLog("error", "push_retry_finalization_failed", { error_code: finalizeError.code });
    }
    structuredLog("error", "apns_jwt_creation_failed", {
      error_type: error instanceof Error ? error.name : "unknown_error"
    });
    throw new Error("push_delivery_retryable");
  }

  const deliveryResults = await Promise.allSettled(
    claimedDevices.map((device) => sendAPNsMessage({
      device,
      notificationType: notification.type,
      environment: device.environment,
      jwt,
      bindings
    }))
  );
  const finalization = deliveryResults.map((result, index) => {
    const device = claimedDevices[index];
    if (result.status === "fulfilled") {
      return {
        event_id: message.eventID,
        device_id: device.id,
        outcome: result.value.outcome,
        apns_status: result.value.status,
        error_code: result.value.errorCode
      };
    }
    return {
      event_id: message.eventID,
      device_id: device.id,
      outcome: "retry",
      apns_status: null,
      error_code: "request_failed"
    };
  });

  const { error: finalizeError } = await serviceClient.rpc("finalize_community_push_deliveries", {
    target_deliveries: finalization
  });
  if (finalizeError) {
    structuredLog("error", "push_delivery_finalization_failed", { error_code: finalizeError.code });
    throw new Error("push_delivery_finalize_failed");
  }

  if (finalization.some((delivery) => delivery.outcome === "retry")) {
    throw new Error("push_delivery_retryable");
  }
}

type CloudflareImageDirectUpload = {
  imageID: string;
  uploadURL: string;
};

type CloudflareImagesResponse = {
  success?: boolean;
  result?: {
    id?: string;
    uploadURL?: string;
  };
  errors?: Array<{ code?: number; message?: string }>;
};

type CloudflareImageDetailsResponse = {
  success?: boolean;
  result?: { id?: string; uploaded?: string; variants?: string[] };
};

type CloudflareImagesSigningKeysResponse = {
  success?: boolean;
  result?: { keys?: Array<{ name?: string; value?: string }> };
};

type GoogleVisionResponse = {
  error?: { code?: number; message?: string };
  responses?: Array<{
    error?: { code?: number; message?: string };
    safeSearchAnnotation?: {
      adult?: GoogleVisionLikelihood;
      racy?: GoogleVisionLikelihood;
      violence?: GoogleVisionLikelihood;
    };
  }>;
};

type GoogleVisionLikelihood = "UNKNOWN" | "VERY_UNLIKELY" | "UNLIKELY" | "POSSIBLE" | "LIKELY" | "VERY_LIKELY";
type ImageSafetyOutcome = "passed" | "needs_review" | "rejected" | "unavailable";

type ImageSafetyResult = {
  outcome: ImageSafetyOutcome;
  summary: string;
};

async function createCloudflareImageUpload(
  bindings: Env,
  metadata: { attachmentID: string; groupID: string; uploaderID: string }
): Promise<CloudflareImageDirectUpload | null> {
  const accountID = bindings.CF_IMAGES_ACCOUNT_ID?.trim();
  const apiToken = bindings.CF_IMAGES_API_TOKEN?.trim();
  if (!accountID || !apiToken) {
    structuredLog("error", "cloudflare_images_not_configured");
    return null;
  }

  const form = new FormData();
  // A private asset must never receive a public delivery URL. Each future
  // view will need a server-issued signed URL after authorization and review.
  form.set("requireSignedURLs", "true");
  form.set("metadata", JSON.stringify({
    attachment_id: metadata.attachmentID,
    group_id: metadata.groupID,
    uploader_id: metadata.uploaderID
  }));
  const response = await providerFetch(
    `https://api.cloudflare.com/client/v4/accounts/${encodeURIComponent(accountID)}/images/v2/direct_upload`,
    {
      method: "POST",
      headers: { authorization: `Bearer ${apiToken}` },
      body: form
    }
  );
  const payload = await response.json<CloudflareImagesResponse>().catch(() => null);
  if (!response.ok || !payload?.success || !payload.result?.id || !payload.result.uploadURL) {
    // Do not emit a provider response as it may include operational detail.
    structuredLog("error", "cloudflare_images_direct_upload_creation_failed", {
      status: response.status
    });
    return null;
  }
  return { imageID: payload.result.id, uploadURL: payload.result.uploadURL };
}

async function deleteCloudflareImage(bindings: Env, imageID: string | null): Promise<boolean> {
  const accountID = bindings.CF_IMAGES_ACCOUNT_ID?.trim();
  const apiToken = bindings.CF_IMAGES_API_TOKEN?.trim();
  if (!imageID) return true;
  if (!accountID || !apiToken) return false;
  const response = await providerFetch(
    `https://api.cloudflare.com/client/v4/accounts/${encodeURIComponent(accountID)}/images/v1/${encodeURIComponent(imageID)}`,
    { method: "DELETE", headers: { authorization: `Bearer ${apiToken}` } }
  );
  if (!response.ok && response.status !== 404) {
    structuredLog("error", "cloudflare_images_cleanup_failed", { status: response.status });
    return false;
  }
  return true;
}

async function cloudflareImageWasUploaded(bindings: Env, imageID: string): Promise<boolean> {
  const accountID = bindings.CF_IMAGES_ACCOUNT_ID?.trim();
  const apiToken = bindings.CF_IMAGES_API_TOKEN?.trim();
  if (!accountID || !apiToken) return false;
  const response = await providerFetch(
    `https://api.cloudflare.com/client/v4/accounts/${encodeURIComponent(accountID)}/images/v1/${encodeURIComponent(imageID)}`,
    { headers: { authorization: `Bearer ${apiToken}` } }
  );
  const payload = await response.json<CloudflareImageDetailsResponse>().catch(() => null);
  return response.ok && payload?.success === true && payload.result?.id === imageID &&
    typeof payload.result.uploaded === "string" && payload.result.uploaded.length > 0;
}

async function createCloudflareImageViewURL(bindings: Env, imageID: string): Promise<URL | null> {
  const deliveryURL = await cloudflareImageDeliveryURL(bindings, imageID);
  if (!deliveryURL) return null;

  const signingKey = await cloudflareImagesSigningKey(bindings);
  if (!signingKey) return null;
  const url = new URL(deliveryURL);
  url.searchParams.set("exp", String(Math.floor(Date.now() / 1_000) + (5 * 60)));
  const stringToSign = `${url.pathname}?${url.searchParams.toString()}`;
  const signature = await crypto.subtle.sign(
    "HMAC",
    signingKey.cryptoKey,
    new TextEncoder().encode(stringToSign)
  );
  url.searchParams.set("sig", bytesToHex(new Uint8Array(signature)));
  return url;
}

async function cloudflareImageDeliveryURL(bindings: Env, imageID: string): Promise<string | null> {
  const now = Date.now();
  const cached = cloudflareImageDeliveryCache.get(imageID);
  if (cached && cached.expiresAt > now) {
    cloudflareImageDeliveryCache.delete(imageID);
    cloudflareImageDeliveryCache.set(imageID, cached);
    return cached.deliveryURL;
  }
  if (cached) cloudflareImageDeliveryCache.delete(imageID);

  const accountID = bindings.CF_IMAGES_ACCOUNT_ID?.trim();
  const apiToken = bindings.CF_IMAGES_API_TOKEN?.trim();
  if (!accountID || !apiToken) return null;
  const existingRequest = cloudflareImageDeliveryInFlight.get(imageID);
  if (existingRequest) return existingRequest;

  let request: Promise<string | null>;
  request = (async () => {
    const response = await providerFetch(
      `https://api.cloudflare.com/client/v4/accounts/${encodeURIComponent(accountID)}/images/v1/${encodeURIComponent(imageID)}`,
      { headers: { authorization: `Bearer ${apiToken}` } }
    );
    const payload = await response.json<CloudflareImageDetailsResponse>().catch(() => null);
    const deliveryURL = payload?.success ? payload.result?.variants?.[0] : undefined;
    if (!response.ok || !deliveryURL) {
      structuredLog("error", "cloudflare_images_view_url_lookup_failed", { status: response.status });
      return null;
    }

    if (cloudflareImageDeliveryCache.has(imageID)) cloudflareImageDeliveryCache.delete(imageID);
    while (cloudflareImageDeliveryCache.size >= cloudflareImageDeliveryCacheMaxEntries) {
      const oldestKey = cloudflareImageDeliveryCache.keys().next().value;
      if (oldestKey === undefined) break;
      cloudflareImageDeliveryCache.delete(oldestKey);
    }
    cloudflareImageDeliveryCache.set(imageID, {
      deliveryURL,
      expiresAt: Date.now() + (cloudflareImageDeliveryCacheTTLSeconds * 1_000)
    });
    return deliveryURL;
  })().finally(() => {
    if (cloudflareImageDeliveryInFlight.get(imageID) === request) {
      cloudflareImageDeliveryInFlight.delete(imageID);
    }
  });
  cloudflareImageDeliveryInFlight.set(imageID, request);
  return request;
}

async function cloudflareImagesSigningKey(bindings: Env): Promise<CloudflareImagesSigningKeyCache | null> {
  const now = Math.floor(Date.now() / 1_000);
  if (cloudflareImagesSigningKeyCache && cloudflareImagesSigningKeyCache.expiresAt > now) {
    return cloudflareImagesSigningKeyCache;
  }
  const accountID = bindings.CF_IMAGES_ACCOUNT_ID?.trim();
  const apiToken = bindings.CF_IMAGES_API_TOKEN?.trim();
  if (!accountID || !apiToken) return null;
  const response = await providerFetch(
    `https://api.cloudflare.com/client/v4/accounts/${encodeURIComponent(accountID)}/images/v1/keys`,
    { headers: { authorization: `Bearer ${apiToken}` } }
  );
  const payload = await response.json<CloudflareImagesSigningKeysResponse>().catch(() => null);
  const key = payload?.success ? payload.result?.keys?.find((item) => item.name === "default")?.value ?? payload.result?.keys?.[0]?.value : undefined;
  if (!response.ok || !key) {
    structuredLog("error", "cloudflare_images_signing_key_lookup_failed", { status: response.status });
    return null;
  }
  const cryptoKey = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(key),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"]
  );
  cloudflareImagesSigningKeyCache = { key, cryptoKey, expiresAt: now + (10 * 60) };
  return cloudflareImagesSigningKeyCache;
}

async function scanCloudflareImageSafety(bindings: Env, imageID: string): Promise<ImageSafetyResult> {
  const accountID = bindings.CF_IMAGES_ACCOUNT_ID?.trim();
  const imagesToken = bindings.CF_IMAGES_API_TOKEN?.trim();
  const visionKey = bindings.GOOGLE_VISION_API_KEY?.trim();
  if (!accountID || !imagesToken || !visionKey) {
    return { outcome: "unavailable", summary: "safety_scan_unavailable" };
  }

  const imageResponse = await providerFetch(
    `https://api.cloudflare.com/client/v4/accounts/${encodeURIComponent(accountID)}/images/v1/${encodeURIComponent(imageID)}/blob`,
    { headers: { authorization: `Bearer ${imagesToken}` } }
  );
  if (!imageResponse.ok) {
    structuredLog("error", "cloudflare_images_scan_download_failed", { status: imageResponse.status });
    return { outcome: "unavailable", summary: "safety_scan_unavailable" };
  }
  const imageBytes = await imageResponse.arrayBuffer();
  if (imageBytes.byteLength < 1 || imageBytes.byteLength > 10_485_760) {
    return { outcome: "rejected", summary: "image_size_invalid" };
  }

  const visionResponse = await providerFetch(`https://vision.googleapis.com/v1/images:annotate?key=${encodeURIComponent(visionKey)}`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      requests: [{
        image: { content: base64Encode(imageBytes) },
        features: [{ type: "SAFE_SEARCH_DETECTION", maxResults: 1 }]
      }]
    })
  });
  const payload = await visionResponse.json<GoogleVisionResponse>().catch(() => null);
  const annotation = payload?.responses?.[0]?.safeSearchAnnotation;
  if (!visionResponse.ok || payload?.responses?.[0]?.error || !annotation) {
    // The provider response contains no user content; retain only its compact
    // status/message for operational diagnosis and never log image bytes.
    structuredLog("error", "google_vision_safety_scan_failed", {
      status: visionResponse.status,
      provider_error: payload?.error?.message ? "provider_error" : "no_provider_message"
    });
    return { outcome: "unavailable", summary: "safety_scan_unavailable" };
  }

  const likelihoods = [annotation.adult, annotation.racy, annotation.violence];
  if (likelihoods.some((likelihood) => likelihood === "LIKELY" || likelihood === "VERY_LIKELY")) {
    return { outcome: "rejected", summary: "automated_safety_flag" };
  }
  if (likelihoods.some((likelihood) => likelihood === "POSSIBLE" || likelihood === "UNKNOWN" || likelihood === undefined)) {
    return { outcome: "needs_review", summary: "automated_safety_review" };
  }
  return { outcome: "passed", summary: "automated_safety_passed" };
}

async function processCommunityMediaScanMessage(
  bindings: Env,
  message: CommunityMediaScanMessage
): Promise<void> {
  const serviceClient = createServiceClient(bindings);
  const { data: claim, error: claimError } = await serviceClient
    .rpc("claim_community_media_scan", {
      target_media_type: message.mediaType,
      target_attachment_id: message.attachmentID
    })
    .maybeSingle<CommunityMediaScanClaim>();
  if (claimError) throw new Error("media_scan_claim_failed");
  if (!claim) return;

  if (claim.terminal) {
    await finishCommunityMediaScan(
      serviceClient,
      message,
      "unavailable",
      "safety_scan_unavailable",
      "scan_attempt_limit_reached"
    );
    return;
  }

  if (!await cloudflareImageWasUploaded(bindings, claim.provider_asset_id)) {
    await finishUnavailableMediaScan(serviceClient, message, claim, "provider_asset_unavailable");
    return;
  }

  const safety = await scanCloudflareImageSafety(bindings, claim.provider_asset_id);
  if (safety.outcome === "unavailable") {
    await finishUnavailableMediaScan(serviceClient, message, claim, "provider_scan_unavailable");
    return;
  }

  await finishCommunityMediaScan(serviceClient, message, safety.outcome, safety.summary, null);
}

async function finishUnavailableMediaScan(
  serviceClient: ReturnType<typeof createServiceClient>,
  message: CommunityMediaScanMessage,
  claim: CommunityMediaScanClaim,
  errorCode: string
): Promise<void> {
  const terminal = claim.attempt_count >= communityMediaScanMaxAttempts;
  await finishCommunityMediaScan(
    serviceClient,
    message,
    terminal ? "unavailable" : "retry",
    "safety_scan_unavailable",
    errorCode
  );
  if (!terminal) throw new Error("media_scan_retryable");
}

async function finishCommunityMediaScan(
  serviceClient: ReturnType<typeof createServiceClient>,
  message: CommunityMediaScanMessage,
  outcome: "retry" | "passed" | "needs_review" | "rejected" | "unavailable",
  summary: string,
  errorCode: string | null
): Promise<void> {
  const { error } = await serviceClient.rpc("finish_community_media_scan", {
    target_media_type: message.mediaType,
    target_attachment_id: message.attachmentID,
    target_outcome: outcome,
    target_summary: summary,
    target_error: errorCode
  });
  if (error) throw new Error("media_scan_state_update_failed");
}

function isCommunityMediaScanMessage(value: unknown): value is CommunityMediaScanMessage {
  if (!value || typeof value !== "object") return false;
  const record = value as Record<string, unknown>;
  return record.version === 1
    && record.kind === undefined
    && (record.mediaType === "group" || record.mediaType === "direct")
    && typeof record.attachmentID === "string"
    && isUUID(record.attachmentID);
}

function isPushSignalTable(value: unknown): value is PushSignalTable {
  return value === "community_notifications"
    || value === "community_message_signals"
    || value === "community_group_chat_signals";
}

function isPushWebhookTable(value: unknown): value is PushWebhookTable {
  return isPushSignalTable(value) || value === "community_group_chat_push_fanout_jobs";
}

function isCommunityPushDeliveryMessage(value: unknown): value is CommunityPushDeliveryMessage {
  if (!value || typeof value !== "object") return false;
  const record = value as Record<string, unknown>;
  return record.version === 1
    && record.kind === "push_delivery"
    && isPushSignalTable(record.sourceTable)
    && typeof record.eventID === "string"
    && isUUID(record.eventID);
}

function isCommunityGroupChatFanoutMessage(value: unknown): value is CommunityGroupChatFanoutMessage {
  if (!value || typeof value !== "object") return false;
  const record = value as Record<string, unknown>;
  return record.version === 1
    && record.kind === "group_chat_fanout"
    && typeof record.jobID === "string"
    && isUUID(record.jobID);
}

function isCommunityMediaCleanupMessage(value: unknown): value is CommunityMediaCleanupMessage {
  if (!value || typeof value !== "object") return false;
  const record = value as Record<string, unknown>;
  return record.version === 1
    && record.kind === "media_cleanup"
    && (record.mediaType === "group" || record.mediaType === "direct")
    && typeof record.attachmentID === "string"
    && isUUID(record.attachmentID)
    && (record.providerAssetID === null || typeof record.providerAssetID === "string");
}

function base64Encode(value: ArrayBuffer): string {
  const bytes = new Uint8Array(value);
  let binary = "";
  for (let index = 0; index < bytes.length; index += 0x8000) {
    binary += String.fromCharCode(...bytes.subarray(index, index + 0x8000));
  }
  return btoa(binary);
}

function bytesToHex(bytes: Uint8Array): string {
  return [...bytes].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

function isUUID(value: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
}

async function claimExpiredCommunityMediaCleanup(
  bindings: Env,
  mediaType: "group" | "direct"
): Promise<CommunityMediaCleanupRow[]> {
  const { data, error } = await createServiceClient(bindings)
    .rpc("claim_expired_community_media_attachments", {
      target_media_type: mediaType,
      target_batch_size: communityMediaCleanupBatchSize
    })
    .returns<CommunityMediaCleanupRow[]>();
  if (error) {
    structuredLog("error", "community_media_cleanup_claim_failed", {
      media_type: mediaType,
      error_code: error.code
    });
    return [];
  }
  if (!Array.isArray(data)) {
    structuredLog("error", "community_media_cleanup_claim_invalid_shape", { media_type: mediaType });
    return [];
  }
  return data.filter((row): row is CommunityMediaCleanupRow =>
    Boolean(row)
      && typeof row.attachment_id === "string"
      && (row.provider_asset_id === null || typeof row.provider_asset_id === "string")
  );
}

async function dispatchExpiredCommunityMediaCleanup(bindings: Env): Promise<void> {
  for (let round = 0; round < communityMediaCleanupDispatchRounds; round += 1) {
    const [directRows, groupRows] = await Promise.all([
      claimExpiredCommunityMediaCleanup(bindings, "direct"),
      claimExpiredCommunityMediaCleanup(bindings, "group")
    ]);
    const messages: CommunityMediaCleanupMessage[] = [
      ...directRows.map((row) => ({
        version: 1 as const,
        kind: "media_cleanup" as const,
        mediaType: "direct" as const,
        attachmentID: row.attachment_id,
        providerAssetID: row.provider_asset_id
      })),
      ...groupRows.map((row) => ({
        version: 1 as const,
        kind: "media_cleanup" as const,
        mediaType: "group" as const,
        attachmentID: row.attachment_id,
        providerAssetID: row.provider_asset_id
      }))
    ];
    if (messages.length === 0) return;

    try {
      await bindings.MEDIA_CLEANUP_QUEUE.sendBatch(messages.map((body) => ({ body })));
    } catch (error) {
      structuredLog("error", "community_media_cleanup_dispatch_failed", {
        error_type: error instanceof Error ? error.name : "unknown_error"
      });
      return;
    }

    if (directRows.length < communityMediaCleanupBatchSize
        && groupRows.length < communityMediaCleanupBatchSize) return;
  }
}

async function processCommunityMediaCleanupMessage(
  bindings: Env,
  message: CommunityMediaCleanupMessage
): Promise<void> {
  if (!await deleteCloudflareImage(bindings, message.providerAssetID)) {
    throw new Error("media_cleanup_provider_delete_failed");
  }

  const { error } = await createServiceClient(bindings).rpc("finalize_community_media_cleanup", {
    target_media_type: message.mediaType,
    target_attachment_id: message.attachmentID
  });
  if (error) throw new Error("media_cleanup_finalize_failed");
}

async function pruneMessageSignals(bindings: Env): Promise<void> {
  try {
    const serviceClient = createServiceClient(bindings);
    const { data: removed, error } = await serviceClient.rpc("prune_community_message_signals", {
      batch_size: 500
    });
    if (error) {
      structuredLog("error", "message_signal_prune_failed", { error_code: error.code });
      return;
    }
    const removedCount = typeof removed === "number" ? removed : Number(removed);
    if (Number.isFinite(removedCount) && removedCount > 0) {
      structuredLog("info", "message_signal_prune_completed", { removed_count: removedCount });
    }
  } catch {
    structuredLog("error", "message_signal_prune_failed", { error_type: "unknown_error" });
  }
}

async function processCommunityProfileMediaCleanup(bindings: Env): Promise<void> {
  const serviceClient = createServiceClient(bindings);
  const { data: rows, error } = await serviceClient
    .from("community_profile_media_cleanup_outbox")
    .select("id, bucket_id, storage_path, attempts")
    .is("processed_at", null)
    .lte("available_at", new Date().toISOString())
    .order("created_at", { ascending: true })
    .limit(100)
    .returns<ProfileMediaCleanupRow[]>();

  if (error) {
    structuredLog("error", "profile_media_cleanup_lookup_failed", { error_code: error.code });
    return;
  }

  let processedCount = 0;
  for (const row of rows ?? []) {
    const nextAttempts = row.attempts + 1;
    const { data: claimed, error: claimError } = await serviceClient
      .from("community_profile_media_cleanup_outbox")
      .update({
        attempts: nextAttempts,
        available_at: new Date(Date.now() + 60 * 60 * 1_000).toISOString()
      })
      .eq("id", row.id)
      .eq("attempts", row.attempts)
      .is("processed_at", null)
      .select("id")
      .maybeSingle();

    if (claimError) {
      structuredLog("error", "profile_media_cleanup_claim_failed", { error_code: claimError.code });
      continue;
    }
    if (!claimed) continue;

    const { error: removeError } = await serviceClient.storage
      .from(row.bucket_id)
      .remove([row.storage_path]);
    if (removeError) {
      const retryDelay = Math.min(
        24 * 60 * 60 * 1_000,
        60 * 60 * 1_000 * (2 ** Math.min(nextAttempts - 1, 5))
      );
      const { error: retryError } = await serviceClient
        .from("community_profile_media_cleanup_outbox")
        .update({
          available_at: new Date(Date.now() + retryDelay).toISOString(),
          last_error: "storage_delete_failed"
        })
        .eq("id", row.id)
        .eq("attempts", nextAttempts)
        .is("processed_at", null);
      if (retryError) {
        structuredLog("error", "profile_media_cleanup_retry_update_failed", { error_code: retryError.code });
      } else {
        structuredLog("error", "profile_media_cleanup_failed", { error_type: removeError.name });
      }
      continue;
    }

    const { error: completeError } = await serviceClient
      .from("community_profile_media_cleanup_outbox")
      .update({ processed_at: new Date().toISOString(), last_error: null })
      .eq("id", row.id)
      .eq("attempts", nextAttempts)
      .is("processed_at", null);
    if (completeError) {
      structuredLog("error", "profile_media_cleanup_completion_failed", { error_code: completeError.code });
    } else {
      processedCount += 1;
    }
  }

  if (processedCount > 0) {
    structuredLog("info", "profile_media_cleanup_completed", { processed_count: processedCount });
  }
}

async function processGroupChatFanoutJob(
  serviceClient: ReturnType<typeof createServiceClient>,
  jobID: string
): Promise<boolean> {
  for (let batch = 0; batch < 10; batch += 1) {
    const { data: hasMore, error } = await serviceClient.rpc("process_community_group_chat_push_fanout", {
      target_job_id: jobID,
      batch_size: 100
    });
    if (error) {
      structuredLog("error", "group_chat_fanout_failed", { error_code: error.code });
      return false;
    }
    if (hasMore !== true) return true;
  }
  return false;
}

async function processPendingGroupChatFanoutJobs(bindings: Env): Promise<void> {
  const serviceClient = createServiceClient(bindings);
  const { data: jobs, error } = await serviceClient
    .from("community_group_chat_push_fanout_jobs")
    .select("id")
    .eq("status", "pending")
    .lte("available_at", new Date().toISOString())
    .order("created_at", { ascending: true })
    .limit(20)
    .returns<Array<{ id: string }>>();
  if (error) {
    structuredLog("error", "pending_group_chat_fanout_lookup_failed", { error_code: error.code });
    return;
  }
  for (const job of jobs ?? []) {
    await processGroupChatFanoutJob(serviceClient, job.id);
  }
}

async function dispatchPendingCommunityMediaScans(bindings: Env): Promise<void> {
  const serviceClient = createServiceClient(bindings);
  const [groupResult, directResult] = await Promise.all([
    serviceClient
      .from("community_group_chat_attachments")
      .select("id")
      .eq("status", "pending_scan")
      .order("created_at", { ascending: true })
      .limit(50)
      .returns<Array<{ id: string }>>(),
    serviceClient
      .from("community_direct_message_attachments")
      .select("id")
      .eq("status", "pending_scan")
      .order("created_at", { ascending: true })
      .limit(50)
      .returns<Array<{ id: string }>>()
  ]);
  if (groupResult.error || directResult.error) {
    structuredLog("error", "pending_community_media_scan_lookup_failed", {
      error_code: groupResult.error?.code ?? directResult.error?.code
    });
    return;
  }

  const messages: CommunityMediaScanMessage[] = [
    ...(groupResult.data ?? []).map(({ id }) => ({ version: 1 as const, mediaType: "group" as const, attachmentID: id })),
    ...(directResult.data ?? []).map(({ id }) => ({ version: 1 as const, mediaType: "direct" as const, attachmentID: id }))
  ];
  if (messages.length === 0) return;

  try {
    await bindings.MEDIA_SCAN_QUEUE.sendBatch(messages.map((body) => ({ body })));
  } catch (error) {
    structuredLog("error", "pending_community_media_scan_dispatch_failed", {
      error_type: error instanceof Error ? error.name : "unknown_error"
    });
  }
}

function normalizedOptionalText(value: unknown, maximumLength: number): string | null | undefined {
  if (value === undefined || value === null) return null;
  if (typeof value !== "string") return undefined;
  const normalized = value.trim();
  return normalized.length <= maximumLength ? normalized || null : undefined;
}

type ReportRow = {
  id: string;
  target_type: "profile" | "post" | "comment" | "event" | "group" | "message" | "group_message";
  target_id: string;
};

async function loadModerationTarget(serviceClient: ReturnType<typeof createServiceClient>, report: ReportRow) {
  switch (report.target_type) {
    case "post":
      return serviceClient
        .from("community_posts")
        .select("id, author_id, body, kind, group_id, created_at, updated_at, moderation_state")
        .eq("id", report.target_id)
        .maybeSingle();
    case "comment":
      return serviceClient
        .from("community_comments")
        .select("id, post_id, author_id, body, created_at, updated_at, moderation_state")
        .eq("id", report.target_id)
        .maybeSingle();
    case "profile":
      return serviceClient
        .from("community_profiles")
        .select("user_id, display_name, username, norway_status, is_public, moderation_state, created_at, updated_at")
        .eq("user_id", report.target_id)
        .maybeSingle();
    case "group":
      return serviceClient
        .from("community_groups")
        .select("id, name, slug, description, scope, city_or_region, visibility, created_by, moderation_state, created_at")
        .eq("id", report.target_id)
        .maybeSingle();
    case "message":
      return serviceClient
        .from("community_messages")
        .select("id, conversation_id, sender_id, body, created_at, deleted_at")
        .eq("id", report.target_id)
        .maybeSingle();
    case "group_message":
      return serviceClient
        .from("community_group_chat_messages")
        .select("id, group_id, sender_id, body, created_at, updated_at, moderation_state")
        .eq("id", report.target_id)
        .maybeSingle();
    // Event enforcement deliberately remains out of this slice. It needs an
    // RSVP/cancellation policy rather than a generic content-state change.
    case "event":
      return serviceClient
        .from("community_events")
        .select("id, host_id, title, description, area_label, starts_at, group_id, created_at, updated_at")
        .eq("id", report.target_id)
        .maybeSingle();
  }
}

export default {
  fetch: app.fetch,
  async queue(batch: MessageBatch<CommunityQueueMessage>, env: Env): Promise<void> {
    for (const message of batch.messages) {
      const body = message.body;
      if (
        !isCommunityMediaScanMessage(body)
        && !isCommunityMediaCleanupMessage(body)
        && !isCommunityPushDeliveryMessage(body)
        && !isCommunityGroupChatFanoutMessage(body)
      ) {
        structuredLog("error", "invalid_community_queue_message", {
          retry_count: message.attempts
        });
        message.ack();
        continue;
      }

      try {
        if (isCommunityMediaCleanupMessage(body)) {
          await processCommunityMediaCleanupMessage(env, body);
        } else if (isCommunityMediaScanMessage(body)) {
          await processCommunityMediaScanMessage(env, body);
        } else if (isCommunityPushDeliveryMessage(body)) {
          await processCommunityPushDelivery(env, body);
        } else {
          const handled = await processGroupChatFanoutJob(createServiceClient(env), body.jobID);
          if (!handled) throw new Error("group_chat_fanout_retryable");
        }
        message.ack();
      } catch (error) {
        structuredLog("error", "community_queue_processing_failed", {
          error_type: error instanceof Error ? error.name : "unknown_error",
          retry_count: message.attempts
        });
        message.retry({
          delaySeconds: isCommunityMediaCleanupMessage(body)
            ? communityMediaCleanupRetryDelaySeconds
            : isCommunityMediaScanMessage(body)
              ? communityMediaScanRetryDelaySeconds
              : communityPushDeliveryRetryDelaySeconds
        });
      }
    }
  },
  scheduled(_controller: ScheduledController, env: Env, ctx: ExecutionContext) {
    ctx.waitUntil(Promise.all([
      dispatchPendingCommunityMediaScans(env),
      dispatchExpiredCommunityMediaCleanup(env),
      pruneMessageSignals(env),
      processPendingGroupChatFanoutJobs(env),
      processCommunityProfileMediaCleanup(env)
    ]).then(() => undefined));
  }
} satisfies ExportedHandler<Env, CommunityQueueMessage>;
