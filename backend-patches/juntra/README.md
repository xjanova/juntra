# Backend patches for Juntra ↔ Thaiprompt-Affiliate

> **Apply these to `xjanova/Thaiprompt-Affiliate` (branch `claude/Main`) before
> the first Juntra production build.**

The Juntra mobile app reuses everything Thaiprompt-Affiliate already has:
- AI provider pool (`FortuneAIService` — Gemini 2.5-flash + Claude + Groq, with
  `purpose` filter, `Cache::lock` per-key serialization, and self-healing)
- Sanctum auth + user accounts
- Payment handlers (PromptPay/TrueMoney/Stripe)
- MLM affiliate engine (`fortune_referrals`, `fortune_commissions`)
- All `fortune_*` tables (readings, credits, celtic questions, mystic posts, ...)

What's missing is **mobile-facing API endpoints** that wrap those services
(currently exposed only via Facebook Messenger / LINE webhooks).

## 📋 Scope of patches

### 1. New routes (in `routes/api.php`)

```php
Route::prefix('v1')->middleware(['auth:sanctum'])->group(function () {

    // ─── Fortune (Juntra mobile) ─────────────────────────────
    Route::prefix('fortune')->name('api.juntra.fortune.')->group(function () {
        Route::get('/categories',  [\App\Http\Controllers\Api\Juntra\FortuneController::class, 'categories'])->name('categories');
        Route::get('/spreads',     [\App\Http\Controllers\Api\Juntra\FortuneController::class, 'spreads'])->name('spreads');
        Route::get('/credits',     [\App\Http\Controllers\Api\Juntra\FortuneController::class, 'credits'])->name('credits');
        Route::get('/history',     [\App\Http\Controllers\Api\Juntra\FortuneController::class, 'history'])->name('history');
        Route::post('/draw',       [\App\Http\Controllers\Api\Juntra\FortuneController::class, 'draw'])->name('draw');
        Route::post('/read',       [\App\Http\Controllers\Api\Juntra\FortuneController::class, 'read'])->name('read');
        Route::get('/readings/{id}', [\App\Http\Controllers\Api\Juntra\FortuneController::class, 'show'])->name('show');
    });

    // ─── Mae Mor AI Chat ─────────────────────────────────────
    Route::prefix('chat/mae-mor')->name('api.juntra.chat.')->group(function () {
        Route::post('/start', [\App\Http\Controllers\Api\Juntra\ChatController::class, 'start'])->name('start');
        Route::post('/send',  [\App\Http\Controllers\Api\Juntra\ChatController::class, 'send'])->name('send');
        Route::get('/sessions/{id}', [\App\Http\Controllers\Api\Juntra\ChatController::class, 'show'])->name('show');
    });

    // ─── Natal chart (Swiss Ephemeris server-side) ───────────
    Route::prefix('natal')->name('api.juntra.natal.')->group(function () {
        Route::post('/compute',       [\App\Http\Controllers\Api\Juntra\NatalController::class, 'compute'])->name('compute');
        Route::get('/daily-transit',  [\App\Http\Controllers\Api\Juntra\NatalController::class, 'dailyTransit'])->name('transit');
    });

    // ─── Affiliate (already exists in part — wrap for mobile) ─
    Route::prefix('affiliate')->name('api.juntra.affiliate.')->group(function () {
        Route::get('/dashboard',    [\App\Http\Controllers\Api\Juntra\AffiliateController::class, 'dashboard']);
        Route::get('/downline',     [\App\Http\Controllers\Api\Juntra\AffiliateController::class, 'downline']);
        Route::get('/commissions',  [\App\Http\Controllers\Api\Juntra\AffiliateController::class, 'commissions']);
        Route::get('/link',         [\App\Http\Controllers\Api\Juntra\AffiliateController::class, 'link']);
    });

    // ─── Payment ─────────────────────────────────────────────
    Route::prefix('payment')->name('api.juntra.payment.')->group(function () {
        Route::get('/methods',           [\App\Http\Controllers\Api\Juntra\PaymentController::class, 'methods']);
        Route::post('/initiate',         [\App\Http\Controllers\Api\Juntra\PaymentController::class, 'initiate']);
        Route::get('/{id}/status',       [\App\Http\Controllers\Api\Juntra\PaymentController::class, 'status']);
    });
});
```

### 2. New controllers (skeletons)

Create under `app/Http/Controllers/Api/Juntra/`:

- `FortuneController.php` — wraps `FortuneAIService` and `FortuneReading` model
- `ChatController.php` — wraps `FortuneConversationService` for in-app chat
- `NatalController.php` — calls Swiss Ephemeris (or simplified Meeus) for chart
- `AffiliateController.php` — wraps existing `FortuneCommission` engine
- `PaymentController.php` — wraps existing `PaymentService`

**Critical:** `FortuneController::read` MUST call the existing
`FortuneAIService::getResponse()` so Juntra inherits the AI provider pool
(Gemini 2.5-flash with `thinkingBudget: 0`, Cache::lock, self-healing,
`purpose=prediction` filtering — see commit `b8fda4ede` and `b4d586907`).

### 3. AI key purpose

Add a new `'chat'` flag column entry value if not present (it should already
exist per migration `2026_05_02_160000_add_purpose_to_ai_api_keys`).

For Juntra usage, both `prediction` and `chat` purposes apply:
- `/v1/fortune/read` → `purpose='prediction'` (long-form deep readings)
- `/v1/chat/mae-mor/send` → `purpose='chat'` (short conversational)

### 4. Update endpoint (auto-update support)

NOT a new endpoint — Juntra calls GitHub Releases directly. No backend
patch needed for auto-update.

## 🚀 Apply

```bash
cd ~/domains/main.thaiprompt.online/public_html
git fetch
git checkout -b feat/juntra-mobile-api
# ... apply controllers + routes manually using Claude Code or by hand ...
git add app/Http/Controllers/Api/Juntra routes/api.php
git commit -m "feat(juntra): add /v1/fortune /v1/chat /v1/natal /v1/affiliate /v1/payment for mobile app"
git push origin feat/juntra-mobile-api
# ... open PR + merge ...
php artisan route:cache
```

## 🧪 Smoke test

```bash
TOKEN=$(curl -s https://main.thaiprompt.online/api/v1/login \
  -d 'email=test@example.com&password=secret' | jq -r .data.token)

curl -s https://main.thaiprompt.online/api/v1/fortune/categories \
  -H "Authorization: Bearer $TOKEN" | jq .

curl -s -X POST https://main.thaiprompt.online/api/v1/fortune/draw \
  -H "Authorization: Bearer $TOKEN" \
  -d 'spread=3card&category=love&question=ความรักจะเป็นอย่างไร' | jq .
```
