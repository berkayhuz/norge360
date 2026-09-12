# Group Messaging Safety Design

## Scope and release order

Group messaging is delivered in independent, safe slices. A control is not
shown in the iOS app until its database authorization, reporting, blocking,
empty/error state, and retention behaviour exist.

1. Member-only, plain-text group chat.
2. Member-only image attachments using Cloudflare Images private, signed delivery.
3. Video and GIF attachments with strict size, duration, and media-processing
   limits.
4. Recipient-scoped, single-view media with expiry and deletion processing.

## Authorization

- Only a current, non-banned group member may read or send group messages.
- All mutations are authenticated RPCs; the iOS client has no direct INSERT,
  UPDATE, or DELETE access to group chat rows.
- Removing or banning a member immediately revokes their read and send access.
- A personal block hides the blocker and blocked member's messages from each
  other. It does not reveal either party's identity to other members.
- Group owner/admin/moderator roles may act only within their own group and
  every destructive moderation action receives an immutable audit record.

## Abuse prevention

- Text is normalized, bounded, and rate-limited server-side.
- Every message has report and "delete for me" actions before the UI ships.
- Reports enter the existing server-side moderation queue; no privileged
  moderation credential is present in the iOS app.
- Notifications carry only a generic event signal. They never carry a message
  body, attachment URL, sender-supplied title, or conversation identifier.

## Attachment storage

- Images are staged in Cloudflare Images with `requireSignedURLs=true` and
  metadata scoped to the attachment, group, and uploader. Public buckets and
  permanent public URLs are prohibited.
- The worker issues narrowly-scoped, short-lived upload/download URLs after it
  re-checks membership and block state.
- A completed upload is downloaded Worker-to-Worker from Cloudflare Images and
  evaluated by Google Vision SafeSearch. Likely or very-likely adult, racy, or
  violent content is rejected; ambiguous and unavailable results remain in
  `pending_review`. No client can move an item to `ready`.
- Cloudflare Images is used for private storage and transformations, not as
  malware/CSAM scanning. Google Vision is an additional safety signal, not a
  substitute for malware scanning, CSAM matching, rate limits, or a reviewer
  decision before delivery is built.
- The server validates MIME type, byte length, image dimensions, video
  duration, and attachment count. Client-provided metadata is not trusted.
- GIFs use the same private attachment pipeline; remote GIF URLs are not
  embedded directly in chat rows.
- Virus/malware scanning and image/video transcoding must complete before a
  media item becomes visible to recipients.
- A sender may cancel an unattached preview only while they remain an active,
  non-banned group member. The Worker atomically claims the attachment before
  deleting its private provider asset and metadata; attached media cannot use
  this path.
- An hourly bounded cleanup removes incomplete uploads after one hour and
  unattached ready/rejected previews after one day. `pending_review` media is
  retained for moderation and never silently deleted by the cleanup job.

## Single-view media

- Single-view media is encrypted/private at rest and has an explicit expiry
  timestamp plus server-side deletion job.
- Only the intended recipient can obtain a one-time, short-lived download URL.
- The UI clearly says that a screenshot cannot be technically prevented.
- A sender may revoke an unviewed item. View/revoke/expiry events are audited.
- Disappearing media is never included in push previews, in-app notification
  previews, analytics, or backups beyond the defined security-retention window.

## Operational requirements

- Production and development APNs devices coexist; the worker routes each
  record to the environment stored for that device.
- Upload, send, report, ban, and read paths require integration tests with two
  members, a removed member, a banned member, and a blocked pair.
- Retention jobs must be idempotent and observable without logging message
  text, media URLs, APNs tokens, or credentials.
