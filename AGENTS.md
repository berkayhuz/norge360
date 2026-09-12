# AGENTS.md — Norge360

## 1. Project Overview

**Project name:** Norge360  
**Domain:** `norge360.com`  
**Initial product:** Norway Community & Relocation Platform — Native iOS App  
**Initial platform:** iOS  
**Mobile technology:** Swift + SwiftUI  
**Primary audience:** People planning to move to Norway, newly arrived residents, established residents who help others, and visitors to Norway  
**Primary language:** English  
**Additional languages:** Norwegian (Bokmål), Turkish  
**Product stage:** MVP

Norge360 is a purpose-built, moderated community for people whose lives or trips connect them to Norway. It is not a generic news feed, an unmoderated social network, or a generic content portal.

The first MVP is a **native iOS application built with Swift and SwiftUI**.

The initial product must solve two connected problems:

> “I am coming to, newly living in, or visiting Norway. How do I find trustworthy guidance and people relevant to my situation?”

The product should combine a personalized, actionable relocation plan with safe community discovery, local conversations, and real-world meetups.

The long-term vision is:

> **Norge360 — Everything you need for Norway.**

The relocation planner remains a first-class product area. Community profiles, a feed, discovery, groups, follows, notifications, and moderated conversations are product areas. Jobs, housing marketplaces, payments, and AI assistance remain out of scope unless explicitly requested.

---

## 2. Core Product Principles

All agents working on this repository must follow these principles.

### 2.1 Useful connection over generic content

Do not build a generic article portal or engagement-driven social feed.

Prefer:

- personalized plans
- checklists
- calculators
- progress tracking
- decision support
- official-source links
- contextual explanations
- city and interest-based groups
- practical questions and helpful answers
- safe, intentional local meetups
- relevant people and conversations

over:

- generic blog posts
- news feeds
- unmoderated forums
- algorithmic outrage or engagement bait
- broad directories

### 2.2 Personalization first

The core value of Norge360 is that two users can receive different plans depending on their circumstances.

At minimum, personalization should consider:

- citizenship / nationality
- EU/EEA status
- reason for moving
- whether the user is already in Norway
- intended length of stay
- destination city
- whether the user is moving alone or with family
- whether the user already has a job offer

Do not hard-code a single universal checklist and present it as valid for everyone.

### 2.3 Official sources are the source of truth

Relocation, immigration, tax, healthcare, identification, employment, and public-service information can change.

Whenever factual procedural guidance is shown, prefer official Norwegian sources.

Preferred sources include:

- UDI
- Skatteetaten
- Politiet
- NAV
- Helsenorge
- Altinn
- Ny i Norge
- Norwegian municipalities
- Statens vegvesen
- other official Norwegian government agencies

Third-party sources may be used only as supplementary context.

Never present uncertain legal, immigration, tax, or public-service information as definitive.

### 2.4 Source transparency

Every procedural task should support metadata such as:

- official source name
- official source URL
- last verified date
- optional short note
- jurisdiction / audience applicability

The UI should make it easy for users to open the official source.

### 2.5 Keep the MVP small and safe

Do not introduce large features simply because they may be useful later.

The first version should focus on:

1. Account setup and a minimal, editable community profile
2. Personalized relocation onboarding and checklist
3. A chronological, relevant community feed
4. City- and interest-based groups
5. Public or private member profiles with a username, avatar, and cover image
6. Search and explainable discovery for people, groups, posts, and tags
7. Question posts, comments, reporting, blocking, and basic moderation
8. Role-based groups, follows, notifications, and private/direct conversations delivered in safe phases
9. Official-source references for procedural information

Features such as AI chat, jobs, housing aggregation, Android apps, marketplace payments, roommate matching, or travel itinerary generation must remain out of scope unless explicitly approved.

The iOS app is **not** future scope; it is the primary MVP product.

---

# 3. MVP User Journey

The preferred first-run experience is:

1. User installs or opens the Norge360 iOS app.
2. User can discover the product before creating an account.
3. When they choose to participate, user creates an account and completes a minimal profile: display name, unique username, preferred language, city/area, and current Norway status.
4. User chooses interests or groups relevant to their situation, such as a city, newcomers, families, students, work, or travel.
5. User reaches a relevant chronological feed and can read, post, comment, join groups, or view events.
6. A user planning a move can start the short relocation questionnaire.
7. The app generates a personalized relocation checklist with official-source references.
8. User can inspect tasks, manage their own progress, and return later to continue.

The MVP must feel like a native iOS product rather than a web page wrapped in a mobile shell.

The experience must work well without requiring the user to understand Norwegian bureaucracy, know anyone locally, or disclose sensitive information.

---

# 4. Account Setup and MVP Onboarding

Account setup should be separate from relocation planning and stay minimal.

Collect only what is needed to make profiles and feeds relevant:

1. Display name (editable)
2. Unique username (editable subject to availability and reserved-name rules)
3. Preferred app language
4. Current relationship to Norway:
   - Planning a move
   - New to Norway
   - Living in Norway
   - Visiting Norway
5. City or region (optional and editable)
6. Interests/groups to follow (optional and editable)

Phone verification is optional for the initial community MVP. Do not block basic use on it until a secure, funded provider and an abuse-prevention plan are in place.

Do not make legal name, exact address, phone number, immigration status, nationality, employer, or travel itinerary public profile fields.

## Relocation Planning Questions

The relocation questionnaire should stay short and be shown only when a user chooses to create a plan.

Recommended questions:

1. What is your citizenship?
2. Are you an EU/EEA citizen?
3. Are you currently in Norway?
4. Why are you moving to Norway?
   - Work
   - Study
   - Family immigration
   - Self-employment / business
   - Other
5. How long do you plan to stay?
6. Which city or municipality are you moving to?
7. Are you moving:
   - Alone
   - With partner
   - With children
   - With partner and children
8. Do you already have a job offer?

Do not ask for sensitive personal data unless required for a clearly defined product feature.

Avoid collecting passport numbers, national identity numbers, bank information, health information, or immigration case identifiers in the MVP.

---

# 5. Personalized Checklist

A relocation plan is made of tasks.

Examples may include:

- Residence permit / registration
- Police appointment
- Norwegian national identity number or D-number
- Population Register actions
- Tax card
- Bank account
- BankID
- Healthcare / fastlege
- Mobile subscription
- Housing
- Deposit account
- Employment onboarding
- School / kindergarten for children

The exact tasks shown must depend on user circumstances.

Do not assume that all users need all tasks.

---

# 6. Task Data Model

Prefer a structured model over page-specific hard-coded content.

A task should be capable of storing fields conceptually similar to:

```ts
type RelocationTask = {
  id: string
  slug: string
  title: string
  shortDescription: string
  category: string

  appliesWhen: RuleSet

  priority: number
  dependencies?: string[]

  steps?: string[]
  requiredDocuments?: string[]

  officialSourceName: string
  officialSourceUrl: string
  lastVerifiedAt: string

  estimatedTime?: string
  deadlineHint?: string

  citySpecific?: boolean
  legalDisclaimer?: string

  translations?: Record<string, Translation>
}
```

The implementation language may differ, but preserve the same separation between:

- task content
- applicability rules
- user state
- completion state

Do not embed user completion state inside the canonical task definition.

---

# 7. Rules Engine

Checklist generation should be deterministic and explainable.

For MVP, prefer a simple rules engine over machine-learning-based decisions.

Example logic:

```text
IF user is non-EU/EEA
AND reason = work
THEN evaluate applicable residence-permit tasks.

IF stay length requires population registration
THEN include relevant registration task.

IF user has children
THEN include school / kindergarten guidance.

IF destination city is known
THEN allow city-specific tasks or links.
```

Rules must be:

- readable
- testable
- versionable
- easy to update when regulations change

Avoid hiding critical eligibility decisions inside large UI components.

---

# 8. Progress Tracking

Each user should be able to mark tasks as:

- Not started
- In progress
- Completed

Optional future states may include:

- Blocked
- Waiting
- Not applicable

The dashboard should show progress such as:

**3 / 9 completed**

or a percentage.

Task completion is user-managed unless the system has a reliable authoritative integration.

Never claim that a government procedure is officially completed merely because a user clicked “Completed.”

---

# 9. Salary & Cost-of-Living Calculator

The calculator should answer a practical question:

> “Can I reasonably live in this Norwegian city with this salary and household?”

Inputs may include:

- annual gross salary
- city
- household type
- number of adults
- number of children
- monthly rent
- transportation assumptions
- optional custom expenses

Outputs may include:

- estimated monthly net income
- rent
- utilities
- food
- transportation
- childcare estimate where appropriate
- estimated disposable income

Important:

- Clearly label estimates as estimates.
- Do not present tax calculations as official tax advice.
- Show assumptions.
- Store tax-year/version information when calculations depend on annual rules.
- Prefer configurable data over magic numbers in components.

---

## Community MVP

Community functionality is part of the MVP, but must be deliberately small, local, and safe.

### Community delivery model

Deliver the community in independent, production-safe vertical slices. Do not expose a UI affordance until its storage, authorization, loading, empty, error, reporting, and blocking behaviour are complete.

1. **Identity and profile:** a public/private Instagram-style profile page, display name, unique username, avatar, cover image, public fields, own-profile editing affordances, and a separate settings destination.
2. **Home and discovery:** Home combines general and group posts. Explore provides focus-aware search for users, groups, posts, and tags; when search is inactive it shows an explainable relevant-post ranking. A chronological fallback must always be possible.
3. **Groups:** city and interest groups with descriptions, slugs, photos, membership requests where applicable, and server-authorized roles. Only a group owner or permitted administrator may alter group settings, roles, membership, posting permissions, bans, or moderation state.
4. **Social graph and notifications:** follows/followers plus in-app notifications with idempotent generation, read state, deletion/archive behaviour, and deep links to a safe destination.
5. **Conversations:** direct and group messaging, attachments, disappearing media, video, and GIFs only after a dedicated security, abuse-prevention, storage-retention, and server-side authorization design is implemented.
6. **Tags:** tag parsing and type-ahead suggestions must be normalized, rate-limited, searchable, and never interpreted as executable markup.

### Conversation delivery and safety requirements

Messaging must be delivered as deliberately bounded vertical slices, in this order:

1. Message requests and accepted **text-only direct conversations**.
2. Read state, blocking, reporting, moderation review, rate limits, and deletion/retention semantics.
3. Server-authorized group conversations with an explicit group-role policy.
4. Attachments, then separately reviewed video, GIF, and disappearing-media capabilities.

For the initial direct-message slice:

- Creating a conversation sends a request; the recipient must explicitly accept it before either party can send messages.
- A block in either direction must prevent discovery, new requests, message reads, and sends at the database boundary.
- Conversation and message access must be enforced by Supabase RLS and security-definer RPCs; do not trust participant IDs, message status, or membership supplied by iOS.
- Limit messages to plain text, normalize whitespace, enforce a bounded length, and rate-limit sends server-side.
- Every message surface must have a report path before it is exposed as a complete product feature.
- Do not send message text, contact data, or membership details to analytics or push-notification payloads.
- Deletion is a user-facing hide/delete action, but the retention policy and moderation/audit requirements must be explicit before hard deletion is introduced.
- Notifications must disclose only that a new message exists, never its body, until a user explicitly opts into a future preview setting.

For the direct-message safety completion slice:

- Read receipts are opt-in privacy data. Persist the member preference server-side and show a receipt only when both conversation participants allow it; never infer a receipt from client UI state.
- “Delete” must begin as a per-member hide action. It must not hard-delete a message body needed for an open safety report, audit review, or a defined retention obligation.
- Any sender-wide removal, attachment expiry, or retention purge requires an explicit server-enforced state transition, authorization check, audit record, and a documented retention window.
- Message delivery, request, and future push notifications must use privacy-safe metadata only. A notification may identify that activity occurred, but must not carry a message body, attachment URL, precise membership data, or sender contact data.

For native iOS push delivery:

- Obtain the APNs device token at launch; never persist it in `UserDefaults` or another client-side cache. Associate it with the authenticated member only through a server-authorized RPC.
- Store devices as revocable server-side records. Deactivate the current token before sign-out, reassign it only through an authenticated registration flow, and deactivate it when APNs reports an invalid or unregistered token.
- Send APNs requests only from a secret-bearing Worker. Database webhooks must authenticate to that Worker with a distinct secret; never embed an APNs key, service-role key, or webhook secret in the iOS app or a migration.
- Push payloads for messages must be generic. They may say that a new message or request exists, but must not include message text, sender identity, attachment URLs, or a conversation identifier.
- Keep APNs development and production environments separate. A development token must never be sent to the production APNs endpoint.

Group chat, media, disappearing content, and GIF search must not be implemented as extensions of a client-only direct-message design. They require their own server-side authorization, anti-abuse limits, storage retention, and moderation review.

### Profile and identity rules

- A member profile is a full navigation destination, not a dialog. The profile tab opens the current member's public-profile presentation with owner-only editing controls and a settings action in the top bar.
- Public profiles may show only intentionally public fields, recent public posts, and aggregate post/like/comment counts. Private profiles must hide these fields, aggregates, posts, and media from other users at the database policy layer, not merely in SwiftUI.
- A username is globally unique, case-insensitive, normalized to lowercase URL-safe ASCII, and is reachable at `norge360.com/{username}` when a public web profile is later enabled. The iOS app must not assume that the web route is already live.
- Usernames must be validated on the server/database boundary. Reserve product, route, protocol, legal, moderation, and future-system slugs (for example `admin`, `api`, `app`, `auth`, `community`, `explore`, `feed`, `groups`, `home`, `messages`, `notifications`, `plan`, `profile`, `search`, `settings`, `support`, `terms`, and `privacy`) as well as variants and unsafe terms.
- Availability feedback may be optimistic in the UI, but the unique database constraint is authoritative. Never promise availability until the save succeeds.

### Navigation and visual rules

- Primary tab order is **Home, Explore, Messages, Plan, Profile** and uses icon-only native tabs with accessible labels.
- Each destination owns its top bar. Profile exposes Settings at top right; Home, Explore, Messages, and Plan expose only actions appropriate to that context.
- Support `system` (default), light, and dark appearance modes. Persist the choice locally and apply it at the app root.
- Posts use a clean, edge-to-edge/content-first presentation without decorative card backgrounds. Status, group context, actions, media, and accessibility semantics must remain clear.

### Discovery and ranking rules

- Do not use opaque engagement maximization. The initial relevant-post ranking may use explicit signals such as recency, followed groups, city/region relevance, and explicit follows. It must not use sensitive relocation answers, private messages, or hidden profile fields.
- Search begins only after deliberate focus/input; while focused with an empty query, show an intentionally empty/search-guidance state rather than silently mixing feed content with results.
- All search queries must be debounced, cancellation-aware, normalized, minimum-length limited where appropriate, and authorized by RLS.

### Community safety and moderation

- Community content is user-generated and must never be presented as official Norwegian guidance.
- Every surface that creates or displays public content must support reporting and blocking before it is considered complete.
- Do not expose a member's email address, phone number, precise address, immigration case details, identity documents, or exact live location.
- Public profile defaults must be conservative: display name and chosen public fields only.
- Posts, comments, groups, events, follows, notifications, conversations, reports, and moderation actions require explicit Supabase RLS policies. A user may only edit or delete their own content; moderation actions require a server-side, auditable role.
- Use Cloudflare Workers for privileged moderation, abuse-prevention, notification fan-out, messaging delivery, destructive/disappearing-media operations, or secret-bearing integrations. Never place moderation credentials in the iOS app.
- Define clear community guidelines and a report-review process before public release.
- Do not build payments, roommate matching, selling, or anonymous posting without explicit approval. Messaging must follow the staged security requirements above.

### Community content rules

- Encourage practical, respectful, locally useful conversations.
- Do not allow legal, tax, immigration, health, or safety claims to be shown as authoritative without a verified official source.
- Community members may share experience, but the UI must label it as community experience rather than official advice.
- Events must use an approximate public meeting area unless the host deliberately shares more detail with confirmed attendees in a future, safety-reviewed feature.

---

# 10. Languages and Internationalization

Initial supported languages:

- `en` — English
- `nb` — Norwegian Bokmål
- `tr` — Turkish
- `ar` — Arabic
- `fa` — Persian
- `fr` — French
- `es` — Spanish
- `de` — German
- `uk` — Ukrainian
- `ru` — Russian
- `pl` — Polish
- `so` — Somali
- `ti` — Tigrinya
- `am` — Amharic
- `ur` — Urdu
- `fa-AF` — Dari

English is the canonical product language and default language for the MVP. Procedural, legal, immigration, and tax translations require editorial review against their official source before being presented as complete.

All user-facing strings should be prepared for localization.

Do not scatter hard-coded UI text throughout components if the project already has or can reasonably use an i18n layer.

Official Norwegian terminology may be preserved where useful, with a plain-language explanation.

Example:

**Skattekort — Tax deduction card**

---

# 11. UX Guidelines

The interface should feel:

- calm
- trustworthy
- practical
- modern
- simple
- non-bureaucratic

Avoid overwhelming users with long pages of government terminology.

Prefer:

- cards
- step-by-step flows
- progress indicators
- concise explanations
- clear CTAs
- visible official sources
- a chronological feed with understandable scope
- visible group context, post date, author display name, and report/block controls
- clear distinction between official sources and community experience
- full-page member profiles with a content-first header, aggregate counts, and clearly bounded owner controls

Good primary CTA examples:

- Create my Norway plan
- Complete profile
- Join group
- Ask the community
- View event
- Continue my plan
- View next step
- Mark as completed
- Open official source

Avoid manipulative urgency.

---

# 12. Website / Landing Page Scope

`norge360.com` is secondary to the iOS MVP.

The website may initially be a lightweight marketing and product-information site with:

- product explanation
- App Store / TestFlight CTA when available
- privacy policy
- terms
- support/contact
- selected public informational pages

Do not duplicate the full iOS product as a web application during the first MVP unless explicitly requested.

The website may later become a full web client that uses the same backend and business rules.

If a web frontend is added, prefer:

- Next.js
- TypeScript
- Cloudflare Workers for deployment
- the same Supabase backend used by the iOS application

Do not let website work delay validation of the native iOS app.

---

# 13. Authentication

Use **Supabase Auth** for authentication.

Authentication should not block initial product discovery.

Prefer allowing users to complete onboarding and preview their generated plan before requiring an account where practical.

An account may be requested when the user wants to:

- create or comment on a post
- join a group or RSVP to an event
- persist progress across devices
- restore the plan after reinstalling
- receive reminders
- synchronize future web/mobile clients
- store preferences

The iOS client must never contain Supabase service-role credentials or other privileged secrets.

Use established Supabase authentication flows and secure iOS credential/session storage.

Never implement custom password cryptography.

---

# 14. Privacy

Follow data-minimization principles.

Only collect data required to provide the requested functionality.

The MVP should avoid storing:

- passport numbers
- national identity numbers
- D-numbers
- BankID credentials
- banking credentials
- health records
- immigration case numbers
- copies of official identity documents

User profile data should be deletable.

User-created posts, comments, event RSVPs, and public profile fields must also be deletable by the user, subject only to narrowly defined legal/security retention requirements. Explain those exceptions in the privacy policy.

Never log secrets or authentication tokens.

Do not expose personal profile data in analytics events.

Supabase RLS must ensure users cannot read or mutate another user's private relocation profile, plan, progress data, drafts, reports, or private contact details. Public community content needs separately designed visibility policies; public does not mean mutable by everyone.

---

# 15. Legal / Safety Boundary

Norge360 is an informational and planning tool.

It is not:

- an immigration lawyer
- a tax advisor
- a government agency
- an official application portal

Relevant screens should make this distinction clear without excessive warnings.

For immigration, tax, healthcare, or legal procedures:

- cite official sources
- show last verification date
- avoid guarantees
- encourage official verification where appropriate

Do not fabricate eligibility rules.

If reliable information is unavailable, say so.

---

# 16. iOS Application Architecture

The first MVP is a native Swift/SwiftUI application.

Prefer a clear feature-oriented structure. A reasonable conceptual layout is:

```text
Norge360/
  App/
  Core/
    Networking/
    Auth/
    Persistence/
    Localization/
    DesignSystem/
  Features/
    Onboarding/
    Community/
    Feed/
    Groups/
    Events/
    Plan/
    TaskDetail/
    Calculator/
    Profile/
  Domain/
    Models/
    Rules/
    Services/
  Resources/
    Localizable.xcstrings
    Assets.xcassets
  Tests/
```

Adapt the structure to the actual Xcode project.

Keep these concerns separate:

- SwiftUI views
- application state
- domain/business rules
- networking
- persistence
- Supabase access
- source/content data
- community visibility, reporting, and moderation state

Do not put immigration or eligibility rules directly inside SwiftUI views.

Use dependency injection or protocol-based boundaries where it materially improves testability, but avoid excessive architecture for a small MVP.

### Preferred iOS implementation style

Prefer:

- Swift
- SwiftUI
- Swift Concurrency (`async` / `await`)
- Apple-native navigation and lifecycle APIs
- URLSession or the official/supported Supabase Swift client for networking
- Keychain-appropriate secure storage for credentials/session material
- Swift-native localization resources
- system components before custom UI controls

Avoid:

- React Native
- Expo
- Flutter
- Capacitor
- WKWebView as the primary app architecture
- JavaScript bridges for core product logic

unless the product direction is explicitly changed.

---

# 17. Glossary

The product should eventually support plain-language explanations for common Norwegian terms such as:

- D-nummer
- fødselsnummer
- Folkeregisteret
- skattekort
- BankID
- fastlege
- depositumskonto
- oppholdstillatelse
- arbeidstillatelse
- Altinn
- NAV
- UDI

Glossary entries should be concise and link to relevant official sources when appropriate.

---

# 18. City Data

Initial cities may include:

- Oslo
- Bergen
- Stavanger
- Trondheim
- Tromsø

Do not attempt to create comprehensive municipality coverage in the first release.

City data should remain modular so additional cities can be added without changing core application logic.

---

# 19. SEO

The web product should be indexable and SEO-friendly where user-specific/private data is not involved.

Potential public landing pages include:

- Move to Norway
- Norway relocation checklist
- Norway salary calculator
- Cost of living in Oslo
- Cost of living in Bergen
- What is a D-number?
- What is BankID?
- Norway tax card guide

Private user dashboards must not be indexable.

Use:

- semantic HTML
- descriptive titles
- metadata
- canonical URLs
- structured data where appropriate
- clean server-rendered/public pages when supported by the framework

Do not create mass low-quality SEO pages.

---

# 20. Accessibility

The iOS app should follow Apple accessibility conventions.

At minimum:

- support Dynamic Type
- provide meaningful accessibility labels/hints where needed
- ensure controls have adequate touch targets
- do not rely on color alone for status
- preserve readable contrast
- support VoiceOver for core flows
- use semantic SwiftUI controls where possible
- ensure progress indicators expose understandable values
- expose icon-only tabs and top-bar buttons with meaningful VoiceOver labels and hints

If public web pages are added, aim for WCAG 2.1 AA-level usability there as well.

---

# 21. Mobile Strategy

The first MVP is **native iOS only**.

Required direction:

- Language: **Swift**
- UI framework: **SwiftUI**
- Primary IDE/project: **Xcode**
- Networking: Swift Concurrency with URLSession and/or the Supabase Swift client
- Backend: Supabase PostgreSQL + Supabase Auth + Row Level Security
- Server-only API/business endpoints when needed: Cloudflare Workers, preferably with TypeScript/Hono
- Distribution during testing: TestFlight
- Production distribution: Apple App Store

The iOS application does not require traditional application hosting. The app binary is distributed through Apple; backend services are hosted separately.

Android is not part of the initial MVP.

Do not create a cross-platform abstraction layer merely to prepare for Android.

Build a high-quality iOS application first. Android may be evaluated after product validation.

Possible later iOS capabilities include:

- local/offline caching
- push notifications
- deadline reminders
- widgets
- deep links
- location-aware travel features

Only reminders directly supporting a user’s relocation plan or an event they explicitly joined should be considered early. Never send community marketing notifications by default.

---

# 22. Analytics

Track product usage, not sensitive user details.

Useful events may include:

- onboarding_started
- onboarding_completed
- plan_created
- task_opened
- task_completed
- official_source_clicked
- calculator_started
- calculator_completed
- account_created
- profile_completed
- group_joined
- community_post_created
- community_post_opened
- community_report_submitted
- event_viewed
- event_rsvp_changed

Do not send citizenship, immigration status, family details, profile fields, private contact details, or post/comment free text to third-party analytics unless there is a clear legal and product justification.

Prefer privacy-conscious analytics configuration.

---

# 23. Error Handling

User-facing errors should:

- explain what happened
- preserve entered data where possible
- suggest a next action
- avoid technical jargon

Never expose stack traces or internal implementation details to users.

External official links and source data should fail gracefully.

---

# 24. Testing Requirements

Core business logic must have automated tests.

Priority areas:

### Rules engine

Test combinations such as:

- EU/EEA vs non-EU/EEA
- work vs study vs family
- already in Norway vs planning arrival
- with children vs without children
- short vs long stays

### Calculator

Test:

- zero / missing values
- realistic salary ranges
- household variations
- annual-rule changes
- rounding behavior

### Progress tracking

Test:

- first save
- status transitions
- persistence
- ownership / access control

Do not rely solely on visual/manual testing for eligibility logic.

For iOS code, use the project's established Swift testing approach (Swift Testing and/or XCTest). Prefer unit tests for rules/calculations and targeted UI tests for critical onboarding and progress flows.

---

# 25. Security

Follow the security practices of the chosen framework.

At minimum:

- validate all server-side input
- enforce authorization server-side
- do not trust client-supplied user IDs
- protect authenticated routes
- sanitize unsafe user-generated content
- use parameterized database access
- keep secrets in environment variables
- do not commit `.env` files
- rate-limit abuse-prone endpoints where necessary

The iOS app is an untrusted client. Never ship privileged server secrets inside the application bundle.

Safe-to-client configuration may include public project identifiers and client-safe keys intended by the provider for mobile use, protected by Supabase RLS and server-side authorization.

Keep these server-side only:

- Supabase service-role credentials
- OpenAI or other AI provider secret keys
- payment provider secret keys
- email provider secret keys
- privileged administrative actions

Use Cloudflare Worker secrets or another approved server-side secret store for server-only credentials.

If an AI feature is added later, treat retrieved content and user prompts as untrusted input.

---

# 26. Performance

The iOS onboarding, plan, and task-detail flows should feel responsive on current supported iPhones.

Prefer:

- native SwiftUI components
- async networking
- cancellation-aware tasks
- lightweight view hierarchies
- cached public reference data where appropriate
- progressive loading for remote data
- no unnecessary polling
- optimized images/assets

Do not block the main actor with networking, parsing, or expensive calculations.

The optional public website should also load quickly on mobile networks.

---

# 27. Preferred Engineering Style

When modifying the codebase:

1. Understand the existing architecture before adding abstractions.
2. Make the smallest coherent change that solves the requested task.
3. Reuse existing components and conventions.
4. Keep business rules out of presentation components.
5. Prefer explicit code over clever code.
6. Avoid speculative abstractions for future modules.
7. Add tests for business-critical behavior.
8. Build the relevant Xcode scheme and run applicable automated tests before considering work complete.

Do not rewrite unrelated code.

---

# 28. Technical Direction — Fixed for MVP

Unless this file is explicitly changed, agents must treat the following as the selected MVP architecture.

## iOS client

- **Swift**
- **SwiftUI**
- Xcode project
- Swift Concurrency (`async` / `await`)
- native iOS navigation/lifecycle
- Supabase Swift client where appropriate
- URLSession for custom Norge360 API calls
- local persistence only where needed for UX/offline resilience

Do not replace the iOS client with React Native, Expo, Flutter, or a web wrapper.

## Backend

Use **Supabase** as the primary managed backend:

- Supabase PostgreSQL
- Supabase Auth
- Supabase Row Level Security (RLS)

The iOS application may access Supabase directly for operations that are safe under properly configured RLS policies.

All authorization-sensitive database tables must have appropriate RLS policies before direct client access is considered complete.

## Server-side API

Do not create a separate backend service merely for architectural purity.

Introduce `api.norge360.com` on **Cloudflare Workers** when server-only behavior is required, for example:

- secret-bearing API calls
- AI requests
- privileged administrative operations
- third-party webhooks
- email sending
- payment processing
- protected aggregation/business logic
- operations unsuitable for direct mobile-to-Supabase access

Preferred API implementation when needed:

- Cloudflare Workers
- TypeScript
- Hono

The iOS app and any future web app should share this API rather than creating platform-specific backends.

## Database

The canonical application database is **Supabase PostgreSQL**.

Do not substitute Firebase, Cloudflare D1, Realm Sync, or another primary backend/database without explicit approval.

## Web

The website is secondary during the first MVP.

If/when required:

- Next.js
- TypeScript
- Cloudflare Workers
- GitHub-based deployment
- same Supabase/Auth/backend architecture as the iOS app

## Storage

Do not build document storage in the first MVP.

If object storage becomes necessary later, Cloudflare R2 or Supabase Storage may be evaluated based on the feature's access-control requirements.

## Architecture summary

```text
                    ┌─────────────────────┐
                    │   Native iOS App    │
                    │  Swift + SwiftUI    │
                    └─────────┬───────────┘
                              │
                    Supabase Auth / HTTPS
                              │
                 ┌────────────┴────────────┐
                 │                         │
                 ▼                         ▼
        ┌─────────────────┐      ┌─────────────────────┐
        │    Supabase     │      │ Cloudflare Workers  │
        │ PostgreSQL/Auth │      │ api.norge360.com    │
        │      + RLS      │      │ server-only logic   │
        └────────┬────────┘      └──────────┬──────────┘
                 │                          │
                 └────────────┬─────────────┘
                              │
                              ▼
                     trusted external APIs

Optional later:

norge360.com → Next.js on Cloudflare Workers → same backend
```

---

# 29. Suggested Core Entities

A minimal application may need:

### User

```text
id
email
locale
createdAt
```

### CommunityProfile

```text
userId
displayName
username                   // unique, lowercased, URL-safe; database-enforced
avatarPath?                 // public only when deliberately chosen
coverPath?                  // public only when deliberately chosen
isPublic
norwayStatus                // planningMove | newToNorway | resident | visitor
cityOrRegion?               // optional, never an address
publicLanguages
interests
createdAt
updatedAt
```

Keep private account data separate from public community profile data. Never use an email address as a public identity.

### CommunityGroup

```text
id
name
slug
description
scope                       // city | interest
cityOrRegion?
visibility                  // public | approvalRequired
createdBy
createdAt
```

### GroupMembership

```text
groupId
userId
role                        // member | host | moderator; moderator is server-managed
createdAt
```

### Follow and Notification

```text
followerId
followedUserId
createdAt
```

```text
id
recipientId
actorId?
type                        // follow | post_like | comment | group | moderation
entityType?
entityId?
readAt?
createdAt
```

Notification rows must be generated idempotently, visible only to the recipient, and must not leak private-profile, blocked-user, or private-message information.

### Conversation and Message

```text
conversationId
kind                        // direct | group
createdBy
createdAt
```

```text
conversationId
userId
role                        // member | admin
joinedAt
```

```text
id
conversationId
senderId
body?
attachmentMetadata?
expiresAt?                  // server-enforced for disappearing media
createdAt
deletedAt?
```

Messages and message attachments need independent, deny-by-default RLS policies. Attachment URLs must be short-lived signed URLs; clients must never decide expiration or recipient authorization themselves.

### CommunityPost and Comment

```text
id
authorId
groupId?
body
kind                        // update | question | recommendation
visibility
createdAt
updatedAt
deletedAt?
```

Comments must be separate entities with their own ownership and moderation rules. Do not store comments as unbounded JSON in a post row.

### CommunityEvent and EventRSVP

```text
id
hostId
groupId?
title
description
areaLabel                   // approximate location, not a precise address by default
startsAt
capacity?
visibility
createdAt
```

```text
eventId
userId
status                      // interested | going
createdAt
```

### CommunityReport and UserBlock

```text
id
reporterId
targetType                  // profile | post | comment | event
targetId
reason
createdAt
reviewedAt?
reviewedBy?
```

```text
blockerId
blockedUserId
createdAt
```

Report queues and moderation actions are private. They must not be directly readable or mutable by ordinary users.

### RelocationProfile

```text
userId
citizenship
isEeaCitizen
currentlyInNorway
movingReason
stayDuration
destinationCity
householdType
hasJobOffer
```

### TaskDefinition

```text
id
slug
category
content
applicabilityRules
dependencies
officialSources
lastVerifiedAt
```

### UserTask

```text
userId
taskId
status
completedAt
notes
```

### CalculatorScenario

Optional for MVP.

```text
userId
grossAnnualSalary
city
household
rent
assumptions
result
createdAt
```

Actual database structure should follow the selected framework and normalization needs.

---

# 30. Out of Scope for Initial MVP

Do not build the following without explicit instruction:

- Norway news aggregation
- unmoderated social network
- marketplace payments
- roommate matching
- anonymous public posting
- Android app
- React Native / Expo cross-platform rewrite
- full job marketplace
- scraping FINN.no
- housing marketplace
- travel itinerary engine
- marketplace payments
- immigration application submission
- automatic government-account login
- BankID integration
- document vault
- AI-generated legal conclusions
- full relocation agency CRM
- employer HR dashboard

These may become future Norge360 modules.

---

# 31. Future Roadmap

After validating the iOS community and relocation experience, possible order of expansion:

1. Native iOS identity/profile, Home, Explore, and relocation planner foundations
2. Groups and role-based moderation
3. Follow graph and in-app notifications
4. Conversation security design, then messaging in a separate implementation phase
5. Events and local meetup discovery
6. Salary & Cost Calculator
7. iOS reminder system
8. Lightweight `norge360.com` marketing/public-information site
9. Trusted AI assistant with official-source retrieval
10. Norge360 Work
11. Norge360 Housing
12. Employer relocation dashboard
13. Norge360 Trip
14. Evaluate Android after validation

Do not implement roadmap items merely because they are listed here.

---

# 32. Definition of Done

A feature is not complete until:

- it satisfies the requested user flow
- iOS UI works correctly on supported iPhone sizes
- core screens behave correctly with Dynamic Type and common accessibility settings
- loading, empty, and error states are handled
- relevant accessibility basics are present
- data is validated server-side where applicable
- authorization is enforced
- business-critical logic has tests
- the relevant Xcode scheme builds successfully
- applicable Swift/Xcode tests pass
- no secrets are committed
- no unrelated regressions are introduced
- official factual claims include appropriate source metadata where applicable

---

# 33. MVP Success Criteria

The MVP should make it possible to test these assumptions:

1. Will users complete a minimal community profile and join relevant groups?
2. Do newcomers and visitors find locally relevant conversations useful?
3. Do users feel safe enough to ask questions, report unsafe content, and attend a meetup?
4. Do users find a personalized relocation plan more useful than generic articles?
5. Do users return to update checklist progress or participate in the community?
6. Which groups, posts, events, and relocation tasks attract the most attention?
7. Do users use the salary / living-cost calculator?
8. What do users ask for next: jobs, housing, reminders, travel, or AI help?

Product decisions should be informed by these signals instead of immediately expanding the feature set.

---

# 34. Agent Instructions

When an agent receives a development task:

- First identify whether it belongs to the MVP.
- Treat the native Swift + SwiftUI iOS application as the primary MVP client.
- Preserve the product positioning described in this file.
- Do not silently expand scope.
- Do not invent Norwegian legal or immigration rules.
- Prefer structured data and testable rules.
- Use official Norwegian sources for procedural facts.
- Keep the user's journey simple.
- Protect private user data.
- Make changes consistent with the existing repository.
- Document meaningful assumptions in code or pull-request notes.
- Flag uncertain regulatory logic instead of guessing.

When product ambiguity exists, prefer the choice that makes Norge360:

**simpler, safer, more trustworthy, more personalized, and easier to validate with real users.**
