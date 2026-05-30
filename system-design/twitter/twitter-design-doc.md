# Twitter/X Frontend System Design — Interview Questions

A senior-level question bank for designing X’s web and mobile clients: feed surfaces, real-time social UX, media, live audio, and the scale patterns that shape what the browser is allowed to assume.

---

## 1. Timeline & Home Feed

> The home timeline is the highest-traffic surface. Interviewers expect you to connect cursor pagination, ranking, virtualization, and how backend fan-out constraints show up in the client.

### Core
- How do you model “Following” vs “For You” as separate feed modes with independent scroll position and cache keys?
- Why does the timeline API use cursor-based pagination instead of offset/limit, and what goes in the cursor?
- How do you implement infinite scroll without jank when tweet heights vary (text, polls, 4-up media, quote tweets)?
- What is the “N new posts” banner pattern, and when should tapping it prepend vs replace the visible window?
- How do you prevent duplicate tweets when a real-time event arrives while `fetchNextPage` is in flight?
- How do you keep scroll position stable when the user is reading mid-feed and ranked items reorder above the viewport?
- How do you hydrate a timeline page of tweet IDs into full tweet + author + engagement objects without N+1 UI waterfalls?

### Deep
- How does hybrid fan-out (push timelines for normal accounts, pull merge for high-follower authors) change what the client can assume about freshness and ordering?
- How do you handle cold-start timeline reads where the server falls back to fan-out-on-read — what skeleton and timeout UX do you show?
- How do you implement bi-directional pagination (load older below, load newer above) for “jump to latest” without resetting the virtualizer?
- How do you reconcile algorithmic re-ranking with “don’t reshuffle what I’m reading” — freeze window, version tokens, or separate candidate vs displayed lists?
- How do you prefetch the next cursor page when the user is within three viewports of the bottom without starving the “new tweets” poll?
- How do you surface fan-out lag or partial freshness (“Timeline may be incomplete”) without training users to ignore warnings?

---

## 2. Compose, Posts & Social Actions

> Compose and inline actions are where optimistic UI and failure recovery separate senior answers from CRUD diagrams.

### Core
- How do you structure the compose flow for text, mentions, hashtags, polls, scheduled posts, and reply vs quote vs repost?
- How do you implement optimistic posting — show the tweet immediately, then reconcile with server-assigned ID and timestamps?
- How do you generate and persist a `client_tweet_id` (or equivalent) for idempotent publish on retry?
- How do you roll back optimistic like, repost, and bookmark actions when the API returns 403 or rate-limit errors?
- How do you render a thread — collapsed “Show this thread”, linear reply chain, and “Show more replies” pagination?
- How do you enforce character limits, URL counting, and attachment rules before enabling the Post button?

### Deep
- How do you queue failed publishes offline and replay them on reconnect without duplicate posts?
- How do you store per-account compose drafts in IndexedDB with eviction when storage pressure hits?
- How do you handle “Post” tapped twice — disable button, in-flight lock, or server idempotency key?
- How do you show upload-in-progress for media attached to a draft without blocking the text composer?
- How do you propagate `tweet_deleted` and `tweet_edited` events to every surface showing that tweet (feed, profile, notifications)?
- How do you implement “Undo repost” within the grace window while keeping counts consistent across tabs?

---

## 3. Profiles, Identity & Graph UI

> Profiles are read-heavy, write-light surfaces that still need consistent counters, pinned posts, and block/mute enforcement at render time.

### Core
- How do you layout profile header (avatar, banner, bio, verified badge, subscription labels) with responsive image priorities?
- How do you paginate a user’s tweets, replies, media, and likes as separate tabs with independent cursors?
- How do you show follower/following counts that update in real time without flashing stale numbers?
- How do you handle protected accounts — gating timeline tabs, follow request CTA, and error states?
- How do you deep-link to a specific tweet on a profile (`/status/:id`) and scroll it into view inside the tab feed?
- How do you reflect block, mute, and restrict actions immediately in feeds, search, and suggestions?

### Deep
- How do you implement profile switching in a multi-account client without leaking cookies, cache, or draft state?
- How do you cache profile metadata separately from timeline pages so header paint isn’t blocked on first tweet page?
- How do you render “You’re blocked” vs empty profile vs deleted account with distinct UX and no data leaks?
- How do you handle NSFW/sensitive media interstitials on profile grids without breaking virtualized layouts?
- How do you show community role badges, subscription perks, and verification types without hard-coding every variant in the view layer?
- How do you invalidate profile-scoped caches when the viewed user changes display name or avatar mid-session?

---

## 4. Real-Time Updates & Notifications

> X is event-driven at scale. Expect questions on transport choice, unread math, and not destroying scroll state when the socket fires.

### Core
- When do you use WebSocket vs SSE vs polling for home timeline freshness, and what does each imply for reconnect?
- How do you show lightweight push events (“new tweets available”, live like counts) without refetching the entire feed?
- How do you deduplicate events that also appear in REST pagination responses after reconnect?
- How do you model the notifications tab — grouped by day, by type (mention, repost, follow), and read/unread?
- How do you compute unread notification count vs per-notification `read` state across devices?
- How do you deep-link from a notification into the right tweet, DM, or Space with correct scroll context?

### Deep
- How do you implement exponential backoff on reconnect after a fleet-wide outage without thundering herds?
- How do you batch high-frequency counter updates (likes, reposts) in the UI to avoid re-rendering the whole virtualized list?
- How do you handle out-of-order events — e.g., `tweet_deleted` before `tweet_created` for the same id?
- How do you respect push notification preferences per category while still showing in-app badges?
- How do you implement “mark all read” optimistically while a background sync reconciles with the server?
- How do you test notification grouping and badge math when event payloads omit fields the UI normally hydrates from REST?

---

## 5. Search, Explore & Direct Messages

> Discovery and DMs are separate domains from the home feed — different ranking, privacy boundaries, and pagination contracts.

### Core
- How do you implement typeahead search across accounts, posts, and hashtags with debouncing and cancellation?
- How do you render Explore/Trending with mixed entity types (news, topics, promoted) in one scroller?
- How do you paginate search results and preserve filters (people, latest, media) in the URL for shareable state?
- How do you highlight query terms in tweet snippets without breaking entity parsing (mentions, links, cashtags)?
- How do you model the DM inbox — conversation list, last message preview, unread badge, and request folder?
- How do you load DM message history with cursor pagination and attach read receipts where supported?

### Deep
- How do you implement “search while offline” or degraded mode with a stale local index and clear labeling?
- How do you handle rate-limited search (429) with retry-after UX instead of silent empty results?
- How do you implement encrypted DM indicators, key change warnings, and device trust UI without exposing secrets?
- How do you show typing indicators and presence in DMs without leaking activity to blocked users?
- How do you jump from a tweet mention to the DM thread with the same participant and correct conversation id?
- How do you virtualize DM threads with images, voice notes, and link cards of heterogeneous height?

---

## 6. Media Upload, Playback & Accessibility

> Media is a multi-phase pipeline on the client: chunk upload, processing polls, progressive playback, and a11y metadata.

### Core
- How do you implement the INIT → APPEND → FINALIZE → STATUS chunked upload flow for video in the composer?
- How do you retry individual failed chunks without restarting a multi-hundred-megabyte upload?
- How do you show upload progress, processing state, and failure/retry for GIF vs image vs video?
- How do you render inline images with blurhash/LQIP placeholders and responsive `srcset` from CDN variants?
- How do you implement progressive MP4 or HLS playback with autoplay policies, mute-by-default, and data-saver mode?
- How do you require and edit alt text, and expose it to screen readers in the timeline and lightbox?

### Deep
- How do you cap concurrent uploads per session and prioritize the tweet the user is about to post?
- How do you handle EXIF orientation, animated GIF vs video detection, and client-side downscale before upload?
- How do you implement a media lightbox with keyboard trap, focus return, and swipe gestures on mobile web?
- How do you avoid layout shift when images load above the fold in a virtualized feed — aspect-ratio boxes and `ResizeObserver`?
- How do you surface copyright, sensitive, or geo-restricted media errors returned after processing completes?
- How do you prefetch video manifests for the next visible tweet without blowing mobile bandwidth budgets?

---

## 7. Spaces, Communities & Live Surfaces

> Live audio and communities add role-based UI, moderation controls, and asymmetric media paths (speakers vs listeners).

### Core
- How do you differentiate host, co-host, speaker, and listener roles in the Spaces UI and action menus?
- How do you handle “Request to speak”, promote/demote, and mute controls with optimistic permission updates?
- How do you show live listener count, speaker avatars, and title updates without full room reload?
- How do you render community timelines, rules, moderation queues, and membership join/leave flows?
- How do you discover live Spaces from the dock, notifications, and profile cards with stale-state handling?
- How do you minimize battery and CPU use when the user is a listener-only participant in the background tab?

### Deep
- How do you architect signaling (WebSocket) vs media (WebRTC for speakers, CDN/stream for listeners) on the client?
- How do you recover from ICE failure or mid-Space network switch without dropping the room shell?
- How do you implement live captions, speaker labels, and recording disclosures for accessibility and compliance?
- How do you moderate live audio — report flow, stage removal, and appeal UX tied to real-time room state?
- How do you test Spaces UI when speaker roster events arrive out of order during rapid promotions?
- How do you share a Space link that opens the correct client surface (web vs app) with graceful fallback?

---

## 8. Client State, API Layer & Caching

> Senior candidates separate ephemeral UI, server cache, and transport — and defend GraphQL vs REST vs BFF at X-scale read volume.

### Core
- What belongs in ephemeral UI state vs React Query/SWR cache vs normalized entity store (tweet by id)?
- How do you key timeline queries (`feedMode`, `cursor`, `viewerId`) for correct invalidation on account switch?
- How do you implement stale-while-revalidate for profiles and static config with `revalidateOnFocus` tradeoffs?
- When would a BFF aggregate timeline + suggested users + ads in one round trip vs many parallel REST calls?
- How do you batch or coalesce API requests on first paint without violating rate limits?
- How do you show rate-limit UX — countdown, queue, or downgrade — for post, like, and search actions?

### Deep
- How do you defend GraphQL on a read-heavy feed vs REST + field expansion + CDN edge caching?
- How do you implement cursor-stable cache merges when the server returns overlapping tweet ids across pages?
- How do you use service worker or HTTP cache for emoji fonts, static bundles, and read-only tweet JSON at the edge?
- How do you invalidate “following graph changed” across home, lists, and DMs without global `queryClient.clear()`?
- How do you handle partial GraphQL errors — render timeline with missing attachment hydration vs fail the whole page?
- How do you design ETag/`If-None-Match` for tweet detail while keeping engagement counts fresh?

---

## 9. Auth, Security, Performance & Delivery

> Covers session boundaries, XSS/CSP, multi-account, Core Web Vitals, and how CDN/edge strategy affects first paint.

### Core
- How do you implement OAuth login, token refresh, and session expiry without losing in-flight compose drafts?
- How do you isolate state per logged-in account (tabs, storage namespaces, service worker scopes)?
- How do you mitigate XSS from rendered tweet text, cards, and third-party embeds — sanitization vs CSP?
- How do you code-split by route (home, DM, settings) and defer heavy players (video, Spaces) behind interaction?
- How do you hit LCP and CLS budgets on the timeline with skeletons, fixed media aspect ratios, and font display strategy?
- How do you prefetch likely next routes (profile hover, tweet detail) without starving the active feed’s bandwidth?

### Deep
- How do you store tokens — httpOnly cookies vs memory — and defend against CSRF on mutating endpoints?
- How do you implement Content Security Policy with inline analytics, ads, and user-generated link previews?
- How do you ship a degraded read-only mode when auth refresh fails mid-session?
- How do you use RUM (LCP, INP, CLS) and attribution to tweet card components vs ads vs third-party scripts?
- How do you implement skeleton loaders that match final layout for ads, promoted tweets, and recommendation inserts?
- How do you align CDN cache TTLs with “delete tweet” propagation so users never see resurrected deleted content?

---

## 10. Observability, Testing, i18n & Moderation UI

> Production social clients fail in streams, locales, and policy UX — interviewers probe whether you’ve thought past happy-path renders.

### Core
- What client metrics do you emit for feed freshness lag, socket reconnect rate, and optimistic rollback frequency?
- How do you trace a tweet publish end-to-end with correlation ids across upload, create, and fan-out visibility?
- How do you mock WebSocket/SSE timelines in integration tests with deterministic event ordering?
- How do you test infinite scroll — sentinel firing, duplicate page edges, and virtualizer unmount/remount?
- How do you implement RTL layouts and locale-aware timestamps without breaking truncation and screen readers?
- How do you render “Report”, “Hide”, “Not interested”, and appeal flows without blocking the scroll thread?

### Deep
- How do you build a stream recorder/replay harness for ranking changes and regression-test “no shuffle while reading”?
- How do you load-test optimistic action storms (mass like during live events) in the client metrics pipeline?
- How do you pluralize and interpolate strings with `@mentions` and counts embedded in translated copy?
- How do you implement content warnings, age gates, and government-requested withholdings with geo-aware UI?
- How do you show moderation outcomes (“visibility limited”, “labeled”) on tweets shared across surfaces consistently?
- How do you run visual regression on tweet cards when typography scales for accessibility (200% zoom)?

---

## Killer Scenarios

> Multi-surface questions that tie feed, real-time, media, and policy UX together.

1. **User posts a video thread while on a train, socket drops mid-APPEND, then reconnects on another tab.** Walk through chunk resume, draft state, optimistic thread placement, and duplicate prevention.

2. **Celebrity posts during the Super Bowl; home feed shows “new posts” every second while the user reads a 50-tweet thread mid-scroll.** How do banners, counter batching, fan-out lag, and scroll anchoring interact?

3. **User switches from Account A to Account B with both composes open and different rate-limit buckets.** What happens to caches, sockets, notifications badge, and in-flight uploads?

4. **For You re-ranks the feed while the user has scrolled to tweet 80 of 120; three promoted tweets inject above.** Defend freeze windows, ad insertion contracts, and CLS control.

5. **Space host removes a speaker who is also actively DM’ing the listener.** How do role events, moderation UI, and parallel real-time channels stay consistent?

6. **Deleted tweet still appears from CDN-cached REST for 30s while the socket already emitted `tweet_deleted`.** Client reconciliation, user messaging, and cache key design.

---

*Prep order: timeline + compose + real-time first, then media and API/state layer, then Spaces/communities, then auth/performance and quality/moderation. Use killer scenarios last as 45–60 minute interview rehearsals.*
