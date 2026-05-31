# Slack Frontend System Design — Interview Questions

A comprehensive reference of deep questions across all segments of building Slack's client, organized by theme and difficulty.

---

## 1. Realtime Messaging & WebSocket

> Very common. Slack's entire UX depends on sub-second message delivery via a persistent WebSocket connection.

### Core
- How does the Slack client establish and maintain a WebSocket connection to the Events API?
- What happens when a new message arrives over the socket while the user is scrolled up reading history?
- How do you deduplicate messages that arrive via WebSocket and also appear in a REST history fetch?
- What is a `client_msg_id` and why does Slack use it for optimistic sends?
- How do you handle WebSocket disconnect — reconnect, replay missed events, or full resync?
- How do you order messages when two users send at the same millisecond in a busy channel?

### Deep
- How do you implement exponential backoff on WebSocket reconnect without flooding the server after a fleet-wide outage?
- How do you handle a `message_changed` event that arrives before the original `message` event due to out-of-order delivery?
- What is your strategy when the socket reconnects after 5 minutes offline — incremental sync vs full channel refetch?
- How do you batch or throttle high-frequency socket events (e.g. 50 reactions in a thread during a live event)?
- How do you surface connection state to the user — "Reconnecting…", "Some messages may be delayed" — without being alarming?
- How do you handle Enterprise Grid where a user has sockets open to multiple workspace shards simultaneously?

---

## 2. Channels, Threads & Message Organization

> Core Slack mental model. Interviewers probe whether you understand channels vs threads vs DMs as distinct UI surfaces.

### Core
- How do you model the relationship between a channel, its messages, and thread replies in client state?
- What changes in the UI when a user clicks "Reply in thread" vs sending a message in the main channel feed?
- How do you implement "Also send to #channel" when posting a thread reply?
- How do you show an unread thread indicator on a parent message without opening the thread pane?
- How do you handle switching between #general, a DM, and an open thread pane — what state persists?
- How do you lazy-load older messages when the user scrolls up in a channel with 100k messages?

### Deep
- How do you implement the thread sidebar (flex pane) without re-fetching the entire channel on every open?
- How do you keep thread reply counts and "new replies" badges in sync with the main channel list?
- How do you handle a `message_deleted` event for a message that has 40 thread replies — what stays visible?
- How do you implement Slack Connect shared channels where members from two workspaces see the same channel?
- How do you virtualize a channel message list where messages have wildly different heights (embeds, images, code blocks)?
- How do you implement scroll anchoring when new messages arrive at the bottom while the user is reading history above?

---

## 3. Presence, Typing & Live Indicators

> Signals real-time collaboration depth. Easy to hand-wave — hard to get right at scale.

### Core
- How does Slack communicate online/away/DND presence for workspace members?
- How do you show "Alice is typing…" in a channel with 200 active members without 200 concurrent indicators?
- How do you debounce typing events so every keystroke doesn't emit a socket message?
- How do you handle presence when a user has Slack open on desktop and mobile simultaneously?
- What is the UX when a user's status is "In a meeting" via calendar integration?
- How do you show green active dots in the member list without polling every few seconds?

### Deep
- How do you aggregate typing indicators — show 3 names + "and 4 others" — and for how long?
- How do you handle presence staleness when the WebSocket is connected but the user switched tabs 20 minutes ago?
- How do you implement custom status (emoji + text + expiry) and sync it across clients?
- How do you show huddle/call-in-progress indicators on avatars without leaking call metadata to unauthorized viewers?
- How do you throttle presence updates during a workspace-wide event (all-hands, incident channel spike)?

---

## 4. Message Composer & Rich Formatting

> Slack's input box is deceptively complex — mentions, emoji, files, slash commands, and drafts all coexist.

### Core
- How do you implement @-mention autocomplete that searches users, user groups, and @channel/@here?
- How do you render Slack mrkdwn (`*bold*`, `_italic_`, `<#C123|general>`, `<@U123>`) in sent messages?
- How do you handle emoji `:shortcode:` autocomplete and custom workspace emoji?
- How do you implement slash commands (`/remind`, `/poll`) — client-side routing vs server round-trip?
- How do you preserve an unsent draft per channel when the user switches between conversations?
- How do you handle file drag-and-drop with upload progress, cancellation, and inline preview before send?

### Deep
- How do you implement link unfurling — show a loading skeleton, then replace with a rich attachment card?
- How do you handle a message that exceeds the character limit — hard block, warn, or split?
- How do you implement message scheduling ("Send later") with optimistic UI and timezone display?
- How do you render Block Kit messages (sections, actions, context blocks) from bot integrations?
- How do you implement "Edit message" with inline replacement and propagate `message_changed` to all open views?
- How do you handle paste-from-clipboard that includes both text and an image in one composer action?

---

## 5. Search & Discovery

> Search spans messages, files, channels, and people — a distinct subsystem from the live feed.

### Core
- How do you implement workspace search with filters (from:, in:, has:, before:, after:)?
- How do you show search results that jump the user to the exact message in channel context?
- How do you handle search while offline or with a stale local index?
- How do you differentiate searching messages vs searching for channels/people to join or DM?
- How do you implement recent searches and search suggestions in the quick switcher (Cmd+K)?
- How do you paginate search results without the UI jumping as new results stream in?

### Deep
- How do you highlight search term matches in message snippets without re-parsing full mrkdwn?
- How do you implement the quick switcher — fuzzy match channels, DMs, apps, and recent files in one ranked list?
- How do you handle search across Enterprise Grid orgs where messages live on different workspace shards?
- How do you cache search results so revisiting the same query feels instant?
- How do you implement "jump to date" in a channel as an alternative to scroll-loading months of history?

---

## 6. Notifications & Unread State

> Unread badges drive daily engagement. Getting badge counts wrong erodes trust immediately.

### Core
- How do you compute unread counts per channel — last-read timestamp vs last-seen message ts?
- How do you distinguish a regular unread from an unread @mention (bold badge vs normal)?
- How do you mark a channel as read — on scroll, on focus, on explicit action, or a combination?
- How do you respect per-channel notification preferences (all messages, mentions only, mute)?
- How do you sync read state across desktop, mobile, and web when the user reads on one device?
- How do you handle desktop push notifications without double-notifying an active window?

### Deep
- How do you implement Do Not Disturb — suppress badges, suppress push, or both?
- How do you handle notification bursts in a high-traffic channel during an incident?
- How do you implement thread-specific notification settings ("Follow thread" vs parent channel mute)?
- How do you reconcile badge counts after reconnect when you missed `mark_read` events from another client?
- How do you implement notification grouping on mobile — 47 messages from #incidents becomes one push?
- How do you handle @channel and @here notifications differently from direct @user mentions in the UI?

---

## 7. Auth, Workspaces, Offline & Performance

> Senior-level signal. Covers multitenancy, resilience, and the virtualization needed to ship Slack at scale.

### Core
- How do you implement workspace switching without a full page reload?
- How do you scope all client state (channels, unread, drafts) per workspace to prevent cross-workspace leaks?
- How do you handle OAuth login and token refresh for the Slack API and WebSocket?
- How do you implement SSO/SAML for Enterprise Grid — redirect flow and session persistence?
- How do you queue a message sent while offline and replay it with the same `client_msg_id` on reconnect?
- How do you virtualize the channel sidebar with 500 channels and DMs?

### Deep
- How do you implement Slack Connect where a user from Org A sees a shared channel alongside native Org A channels?
- How do you handle a user who belongs to 30 workspaces — lazy-load sidebar vs eager prefetch?
- How do you implement role-based UI — guest, member, admin, owner — for channel actions?
- How do you implement a degraded-mode UI when the WebSocket is down but REST API still works?
- How do you implement scroll anchoring in a virtualized list when images above the viewport finish loading?
- How do you persist messages and drafts locally — IndexedDB schema, eviction policy, encryption at rest?

---

## 8. The "Killer" Questions

> Questions that separate good candidates from great ones. Each forces multi-system thinking across Slack's subsystems.

1. **User sends a message in #incidents while offline, switches to a DM, then reconnects.** What happens to the optimistic message, the draft in #incidents, badge counts, and ordering? Covers offline queue, workspace-scoped state, optimistic UI, and reconnect replay.

2. **A thread gets 200 replies during a live incident while the user has the thread pane open but scrolled up.** How do unread badges, typing indicators, virtualized scroll, and "new messages" pill interact? Covers threads, virtualization, scroll anchoring, and real-time updates.

3. **User gets @mentioned in #general, #random, and a thread simultaneously while DND is off but #general is muted.** Which notifications fire, what do badges show, and what happens on desktop vs mobile? Covers notification prefs, mention parsing, cross-device sync, and badge math.

4. **Design the quick switcher (Cmd+K) for a user in 25 workspaces with 8,000 total channels.** Covers fuzzy search indexing, virtualization, workspace scoping, recent-items cache, and keyboard navigation performance.

5. **A shared Slack Connect channel has members from two orgs with different retention policies.** How does search, history loading, and file preview behave for each side? Covers multitenancy, Slack Connect, auth boundaries, and policy-aware UI.

6. **WebSocket drops for 90 seconds during a company all-hands with 5,000 messages/min in #announcements.** What does the user see, how do you catch up without freezing the UI, and how do you reconcile duplicate/missed events? Covers reconnect backoff, event dedup, batching, and degraded-mode UX.

---

*Use the segmentation above to time-box your prep. Realtime messaging + channels/threads first, then composer and notifications, then auth/resilience, then killer scenarios.*
