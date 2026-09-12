# Direct-Message Media Safety Design

## Scope and delivery order

Direct messaging remains request-gated. Media is delivered only after text
messaging, blocking, reporting, member-level hiding, private storage and
generic activity signals are already enforced.

1. Private, safety-scanned image attachment — implemented.
2. Private video attachment with independent processing and moderation policy.
3. Recipient-scoped single-view image, then single-view video.

No client UI is exposed for a later step until its server authorization,
retention, reporting, loading, failure and cleanup behaviour exists.

## Authorization and privacy

- The conversation must be active and both participants must be active
  members. A pending request can never be used to upload, attach or view media.
- A block in either direction revokes upload, attachment, read and view access
  at the Worker and database boundaries.
- The iOS app receives no storage path, provider asset ID or permanent URL.
  View URLs are server-authorized and expire in five minutes.
- Every media attachment belongs to one message and is visible only through an
  authorized conversation-message list. A member-level message hide also hides
  its attachment.
- A report targets the message, preserving the existing moderation and audit
  path without duplicating private media metadata into analytics or push data.

## Image implementation

- Images are staged in Cloudflare Images with signed delivery required.
- The Worker checks the authenticated participant, direct-conversation state,
  membership state, blocking state, MIME type and a 10 MB maximum before it
  creates a one-time upload URL.
- Google Vision SafeSearch produces only a normalized result. Rejected or
  ambiguous images never become recipient-visible. The worker, not iOS, is the
  only actor that can mark an attachment ready.
- A sender may cancel an unattached preview. The Worker atomically claims it,
  deletes the provider asset and removes metadata. An hourly cleanup deletes
  incomplete previews after one hour and unattached ready/rejected previews
  after one day. Pending-review media is retained for moderation.

## Video prerequisites

Video is not an image extension. Before it is enabled, the server must add:

- a private video provider/storage configuration distinct from image delivery;
- verified MIME sniffing, maximum byte size, duration, dimensions and codec
  limits performed server-side;
- asynchronous malware scanning, transcoding and thumbnail extraction before
  recipient visibility;
- a moderation policy for video frames and audio, including an explicit review
  path when automated scanning is unavailable or uncertain;
- explicit provider deletion, failed-transcode cleanup, retry limits and an
  idempotent retention job;
- end-to-end tests for participants, third parties, blocked pairs, requests,
  report visibility, cancellation and expiry.

## Single-view media prerequisites

Single-view media is a separate state machine, not a UI timer. It requires
server-enforced states such as `ready`, `delivered`, `viewing`, `viewed`,
`revoked` and `expired`, with auditable transitions.

- Only the intended recipient may claim one short-lived view URL.
- The first claim is atomic; refresh, replay and parallel device attempts must
  not create another view.
- The sender can revoke only an unviewed item. Expiry and revoke jobs delete
  the provider asset after the documented moderation/retention window.
- Screenshot prevention is not promised. The UI states this plainly.
- No media URL, caption, sender identity or conversation identifier is placed
  in APNs, analytics, notification previews or logs.

## Operational guardrails

- Worker logs use only normalized error codes and attachment identifiers when
  necessary; they never include image bytes, video bytes, signed URLs, message
  body, access tokens or user contact data.
- Cleanup and deletion workers are bounded, idempotent and observable with
  aggregate counters only.
- Production media is enabled only after the environment has configured the
  private provider credentials, scanning integration and a reviewer process.
