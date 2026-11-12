# API parity contract — app ↔ จันทรา.online (2026-11)

The website (`xjanova/juntraweb`) moved far ahead of the app (0.6.0, 2026-10-06):
three oracle rooms, follow-up clock, free card, premium voice, review/share,
daily luck, card collection, astrology profile, web push. This file is the
contract the app is built against. juntraweb implements it under `/api/v1`.

Rules for every new endpoint
- Same rules as the web code path it mirrors — reuse the web's Support/Service
  classes (`ChatRooms`, `ReadingQaClock`, `FreeAskClock`, `ReadingRoomLock`,
  `VoicePremium`, `DailyLuck`, `OracleMedia`, `ReadingEngagementController` rules…).
  Never fork a second copy of a rule.
- Envelope `{data: …}`; errors `{message, reason_code, …}` with a Thai `message`
  the app can show as-is.
- Money endpoints take `Idempotency-Key` like the existing ones.
- Additive only: existing keys keep their meaning, so 0.6.0 keeps working.
- The app sends `X-App-Channel: play|direct`. With `play` the server must not
  return PromptPay/QR/bank data (`pending_bill`, top-up channels) — Play policy.
- Absolute `https://` URLs for every media field.
- An old server answers 404 for a new path; the app must fall back gracefully
  (single แม่หมอ room, no clock, features hidden).

## A. Oracle rooms

### A1 `GET /v1/chat/rooms` (public; bearer optional)
```json
{ "data": [ {
    "key": "busaba", "name": "น้องบุษบา", "short": "บุษบา",
    "eyebrow": "…", "title": "…", "quote": "…", "tags": ["ไพ่ 1-5 ใบ", "…"],
    "accent": "#7cc7f6", "open": true,
    "image_url": "https://…/images/juntra/rooms/busaba.webp",
    "product": {"spread": "quick", "name": "ดูไวกับน้องบุษบา", "cards": 3, "price": 39},
    "spreads": ["quick", "single", "three", "love", "career", "decision"],
    "media": {
      "still_url": "https://…",
      "loops": ["https://…/media/oracle/busaba/idle-breathe.mp4", "…"],
      "music": ["https://…/media/oracle/busaba/music/1.mp3", "…"],
      "voice": {"room_greet": "https://…/voice/room_greet.mp3", "…": "…"},
      "voice_by_spread": {"single": {"offer_cards": "https://…/voice/offer_cards--single.mp3"}},
      "theater": {"plate_url": "https://…", "sprite_url": "https://…", "bg_url": "https://…"}
    }
  } ],
  "meta": {
    "chat_cost": 2, "daily_limit": null, "free_daily": false,
    "lede": "คุยฟรีทุกวัน · อยากให้เปิดไพ่เมื่อไรค่อยเลือก …",
    "ai_disclosure": "ผู้พยากรณ์ทุกห้องคือ หมอดู AI …",
    "lock": null
  } }
```
- Order = `ChatRooms::all()` (cheap → expensive). `spreads` = what that room
  sells right now (own spread first), same list the web room menu uses.
- `loops` = the opaque H.264 `.mp4` idle loops only (the app cannot draw VP9 alpha).
- `lock` (only with bearer) = `ReadingRoomLock::active` →
  `{room, until (epoch s), reason: pick|reading|qa, reading_id, message}`.

### A2 `GET /v1/chat/live` (public) — same JSON as web `/chat/live`.

### A3 `POST /v1/chat/conversations` — body `{reading_id?, room?, new?: bool}`
- `reading_id` → unchanged behaviour (room = `ChatRooms::roomForSpread`).
- `room` without `reading_id` → resume the latest conversation of that user with
  `persona = room` and `reading_id IS NULL` (web `conversationFor`), unless `new`.
- closed room → 422 `room_closed`; another room locked → 423 `room_locked` + `lock`.
- No `room` → `maemor` (old clients).

### A4 Conversation object (start / show / list item)
Adds to the current shape:
```json
{ "persona": "busaba",
  "room": {"key": "busaba", "name": "น้องบุษบา", "short": "บุษบา", "image_url": "https://…", "accent": "#7cc7f6"},
  "free_reading_id": null,
  "qa": {"minutes": 7, "started": true, "ends_at": 1731400000, "ended": false, "over": false, "left": 312, "warn": 3, "premium": false},
  "free_ask": {"minutes": 2, "started": false, "ends_at": null, "over": false, "left": 120},
  "pending_bill": null,
  "menu": [{"spread": "love", "locked_until": null}],
  "server_time": 1731399688 }
```
- `qa` = `ReadingQaClock::state`, `free_ask` = `FreeAskClock::state` (null when not applicable).
- `pending_bill` (direct channel only) = the web room bill:
  `{id, ref, amount, payable_amount, qr_payload, expires_at, blocks}`.
- Message objects add `from_admin` (exists) and `admin_as` (`oracle|admin|null`).
- `GET /v1/chat/conversations?room=busaba` filters by persona; list items carry `persona` + `room`.

### A5 `POST /v1/chat/conversations/{id}/send`
Adds `qa`, `free_ask`, `pending_bill`, `server_time`, and `reply_voice` (see C5).
Parity fixes: `kind: "help"` turns are free like the web; follow-up clock over →
409 `qa_over` with `message = ReadingQaClock::overMessage` (no charge); free-ask
over → the web's soft invite + offers (no charge, no AI).

### A6 `POST /v1/chat/conversations/{id}/qa/end` → `{data: {qa, message: farewell}}` (idempotent).

### A7 `GET /v1/chat/conversations/{id}/feed?after={message_id}`
→ `{data: [message…], meta: {held: bool}}` — new messages (staff takeover, nudges).
The app polls it while `held` or while a reply is pending.

### A8 `POST /v1/chat/transcribe` — multipart `audio` (≤ 700 KB, ≤ 25 s) → `{data: {text}}`.
Same limits/throttle as web `/chat/transcribe`.

## B. Packages and config

- `/v1/tarot/packages` items add `room` (`ChatRooms::roomForSpread`), `reader_name`
  (`ChatRooms::readerName`), `web_only` (bool).
- `/v1/app/config` adds
  `voice_premium: {offerable, price, qa_minutes}`, `rooms: true`,
  `free_reading: {enabled}`, `push: {fcm: bool}`, `features.*` flags for every
  new block below (so the app hides what the server does not have).
  Fixed key names (`true` = the endpoint exists on this server):
  `rooms` (A1–A3), `qa_clock` (A4 qa + A6), `free_ask`, `chat_feed` (A7),
  `chat_transcribe` (A8), `voice_premium` (C1 + C5), `reading_share` (C3),
  `reading_review` (C4), `deep_async` (C6), `free_reading` (D), `daily_luck`
  (E1–E2), `collection` (E3), `testimonials` (E4), `account_profile` (F),
  `push` (G). The app shows a new block only when its flag is `true`; a missing
  key = hidden (old server).
- `/v1/wallet` `pricing` adds `tarot_quick`, `tarot_kunsai`, `voice_premium`, `deep`;
  adds `topup: {bundles: [50,100,200,500,1000,2000], min: 20, max: 50000, channels: ["promptpay","kbank"], kbank: {bank, name, number}|null}`
  (omitted for `X-App-Channel: play`).
- `POST /v1/wallet/topup/promptpay` accepts `method: promptpay|kbank` (web parity).

## C. Readings

- C1 `POST /v1/history/readings` accepts `voice_premium: true` → second debit
  (`VoicePremium`, idempotency `voicepass:`), 409 `voice_premium_unavailable` when
  not offerable (nothing charged). Response adds `premium`.
- C2 Reading detail adds `persona`, `room {key,name,short,image_url}`,
  `reader_name`, `premium {status, price}|null`, `review {rating, message, allow_public}|null`,
  `share {public, url}`, `qa_minutes`.
- C3 `POST /v1/history/readings/{id}/share` `{public: bool}` → `{data: {public, url}}`
  (owner only; same rule as web `tarot.share`). The app turns it on before sharing a link.
- C4 `POST /v1/history/readings/{id}/review` `{rating 1-5, message?, allow_public?}`
  → `{data: {review}}` (web `tarot.review` validation).
- C5 Narration (premium only): `POST /v1/history/readings/{id}/voice/next` (same JSON
  as web) and `GET /v1/history/readings/{id}/voice.mp3?…` (bearer, audio/mpeg).
  Chat replies in a premium room carry `reply_voice: {url}|null` (bearer audio).
- C6 Deep: `POST /v1/deep` accepts `mode: async` → 202 + reading id; status via
  `/v1/history/readings/{id}/status` (web `DeepReadingFinisher`).

## D. Free card
- D1 `GET /v1/tarot/free` (bearer) → `{data: {available, reason: claimed|disabled|daily_cap|null, max_chars}}`.
- D2 `POST /v1/tarot/free` `{question}` + Idempotency-Key → `{data: {reading, conversation_id}}`
  (server draws the card — `FreeTarotController@cast` rules; conversation = web `chat.from-free`).

## E. Engagement
- E1 `GET /v1/account/daily-luck` → `{data: {checked_in, streak, next_milestone, earned, reading}}`
  (`reading` = `DailyLuck::reading` once checked in, else null).
- E2 `POST /v1/account/checkin` → same shape (idempotent).
- E3 `GET /v1/account/collection` → `{data: {found, total, favourite, cards: [{slug, name_th, name_en, image_url, count, reversed_count, found}]}}`.
- E4 `GET /v1/testimonials?limit=3` (public) → approved, `allow_public` reviews the web home shows.

## F. Profile
- F1 `GET /v1/account/profile` → `{data: {name, email, phone, birth_date, birth_time, birth_place, zodiac {slug,name_th}|null, chinese_zodiac {slug,name_th}|null, line_id, subscribed}}`.
- F2 `PATCH /v1/account/profile` (any subset of name, birth_date, birth_time, birth_place, line_id, subscribed)
  → same shape; zodiac derived server-side (`Astrology`, Thai sidereal Lahiri).

## G. Push (FCM)
- G1 `POST /v1/push/devices` `{token, platform: "android", channel}` · `DELETE /v1/push/devices` `{token}`.
- G2 `GET|PUT /v1/push/preferences` — same fields as web push preferences.
- Server sends FCM HTTP v1 next to Web Push when `FCM_*` credentials exist; silently off otherwise.

## Deviations reported by the juntraweb side (binding for the app)
- A4 `admin_as` is only ever `"admin"` or `null` — never `"oracle"`. Staff typing
  *as* the oracle arrive as a plain assistant message (the web hides it on
  purpose). Draw the staff label only when `admin_as == "admin"` (= `from_admin`).
- A5 follow-up clock over → 409 `qa_over` (the web uses 403; the API uses 409).
- A6 a repeat `qa/end` returns `message: null` (no second farewell); `qa` is full.
- A5 extra keys: `ai_suggestions` (chips the oracle wrote for this conversation,
  same as the web) next to `suggestions`; new 409 `busy_other` (the same user is
  sending from another device/tab — nothing charged, show "ลองส่งใหม่");
  422 `room_closed` when the conversation's room was closed since it started.

Second batch (juntraweb chat API written, 2026-11-12):
- A1 `accent` is always a hex (`#7cc7f6` · `#a884f4` · `#e0455f`). `media.voice` and
  `media.voice_by_spread` are always objects (`{}` when empty). `media.theater.bg_url`
  is always null (the web has plate + sprite only). `spreads` = tarot spreads only —
  deep reading shows up in `menu` as `spread: "deep"`. `meta.daily_limit` null = no
  limit. `meta.lede` is the full sentence. `meta.lock.until` = epoch seconds.
- A2 `/v1/chat/live` is wrapped: `{data: <web /chat/live JSON>}`.
- A3 423 `room_locked` / 422 `room_closed` only on the `room` path; the `reading_id`
  path is unchanged (no lock check). `room` + `new: true` → 201; resume → 200. Opening
  a room does not call the AI (greeting built locally, like the web).
- A4 `pending_bill` = `{id, ref, amount, payable_amount, qr_payload, expires_at (epoch s),
  has_slip, blocks}`; with `X-App-Channel: play` the key is present and null.
  `menu` items = `{spread ("deep" for deep reading), key, label, cards, price,
  locked_until}` — **`locked_until` is Thai display text** ("15 พ.ย. 2569"), null = open now.
  List items (GET conversations) add only `persona`, `room`, `free_reading_id`; qa,
  free_ask, menu and pending_bill come with start/show/send only. show adds `ai_suggestions`.
- A5 `reply_voice.url` is a **public** Thaiprompt/R2 file URL — fetch it WITHOUT the
  juntraweb bearer (never send the bearer to another host). Every send/held answer
  carries qa, free_ask, pending_bill, menu, server_time. `message` null = degraded
  reply: show `reply` and offer resend as today.
- A6 `qa/end` → `{data: {qa, message: <message object {id, role, content, …}>|null,
  server_time}}` — a full message (append it to the list), null on a repeat.
- A7 feed messages have the same shape as `conversation.messages`.
- A8 transcribe errors: 429 `mic_daily_limit`, 422 `transcribe_failed`, plus the usual
  422 file validation.
- Play: with `X-App-Channel: play` the bot never answers "unpaid bill, scan the QR", and
  a bill opened on the web does not block the menu.
- E1/E2 = `{checked_in, streak, next_milestone {days, label, left}|null,
  earned [{days, label}], reading|null}`; E2 adds `new` (bool) and always answers 200.
- E3 `favourite` = `{slug, name_th, count}|null`; cards not found yet still carry name +
  image (the app draws the card back when `found` is false).
- E4 items = `{name, service, rating, message}`; `?limit` 1..12.
- F1 `phone` = the login number (users.phone, as auth/me) + extra `contact_phone`
  (contact number from the astrology form); F2 never edits email/phone.
- Validation 422 = `{message, reason_code: "validation_failed", errors}`.

## Natal (app only)
The app keeps its on-device natal chart but switches to the web's zodiac:
sidereal = tropical − `ThaiAstro::ayanamsa` (Lahiri). The Dart port is pinned
against values printed by the PHP code (see `test/astronomy/ayanamsa_test.dart`).
