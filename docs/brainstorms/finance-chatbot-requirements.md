---
date: 2026-04-23
topic: finance-chatbot
---

# Finance Chatbot (Chat-first Expense & Income Ledger)

## Problem Frame

Traditional expense trackers lose users to logging friction: open app → tap "add" → pick category → type amount → save. After a week, most people stop. The owner of this project wants a personal finance tool where logging an expense is as cheap as sending a WhatsApp message — "abis beli batagor 5rb" — and the system handles parsing, dating, and categorization automatically so that a monthly ledger exists without manual bookkeeping.

This is a single-user personal tool, not a product for others. It must work from a phone while out and about (e.g., right after a purchase), which means it lives on a real URL, not only on a laptop.

---

## Actors

- A1. **Owner (single user)**: Logs expenses and income by sending natural-language chat messages in Bahasa Indonesia (occasionally mixed with English). Reviews and edits entries in the ledger. Is the only human user of the system.
- A2. **Parser Agent** (Claude Haiku, accessed via the `ruby_llm` gem): Reads each chat message and produces structured entries (amount, direction, category, date, description) or flags that the message is not a transaction. Referred to consistently as "Parser Agent" throughout this document; "Claude Haiku" names the underlying model, not a separate component.
- A3. **Ledger**: Persistent record of all transactions. Single source of truth for "what did I spend and earn."

---

## Key Flows

- F1. **Log an expense via chat**
  - **Trigger:** Owner types a message in the Chat screen (e.g., "abis beli batagor 5rb").
  - **Actors:** A1, A2, A3.
  - **Steps:**
    1. Owner sends message.
    2. System shows the message as an outgoing chat bubble immediately.
    3. Parser Agent extracts: amount, direction (expense/income), category (from fixed list), date (defaulting to today if none given), short description.
    4. System writes the row(s) to the Ledger and replies in chat with a confirmation bubble: "✓ Logged: Rp5.000 — Makanan & Minuman (batagor)".
    5. Confirmation bubble is tappable → opens an inline edit control for amount / category / date / description.
  - **Outcome:** A new Ledger row exists; Owner has visible confirmation and a one-tap path to correct it.
  - **Covered by:** R1, R2, R3, R4, R5, R8, R9.

- F2. **Log income**
  - **Trigger:** Owner sends a message that reads as income (e.g., "gajian 10jt masuk", "dapet transfer 500rb").
  - **Actors:** A1, A2, A3.
  - **Steps:** Same as F1, but Parser Agent sets direction = income and picks an income category (e.g., "Gaji" / "Lainnya").
  - **Outcome:** Ledger row with direction = income.
  - **Covered by:** R3, R4.

- F3. **Correct a mis-parsed entry**
  - **Trigger:** Owner taps a confirmation bubble or a Ledger row whose parsed values are wrong.
  - **Actors:** A1, A3.
  - **Steps:**
    1. Owner taps the bubble or row.
    2. Inline editor appears with amount, direction, category (dropdown from fixed list), date, description.
    3. Owner changes fields and saves.
  - **Outcome:** Row is updated in place. Chat bubble reflects the corrected values.
  - **Covered by:** R9, R10.

- F4. **Handle a non-transaction message**
  - **Trigger:** Owner sends a message with no parseable amount ("halo apa kabar", "oke deh", "liat ledger dong").
  - **Actors:** A1, A2.
  - **Steps:**
    1. Parser Agent detects that this is not a transaction.
    2. System does **not** create a Ledger row.
    3. System replies in chat with a short note, e.g., "Gak ada transaksi yang kecatat dari pesan itu. Coba sebut jumlahnya ya."
  - **Outcome:** Ledger is unchanged; Owner knows the message was ignored (and why).
  - **Covered by:** R6, R7.

---

## Requirements

**Application shape**
- R1. The app has exactly two screens: **Chat** and **Ledger**, reached from two links in the app layout header (or equivalent mobile nav bar). Chat is the default. No settings screen in v1 (category list is a constant).
- R2. The Chat screen presents a WhatsApp-style vertical message list and a single text input pinned at the bottom. Messages from the Owner appear as outgoing bubbles; system replies (confirmations, error notes) appear as incoming bubbles. IDR amounts render via `number_to_currency(n, unit: "Rp ", separator: ",", delimiter: ".", precision: 0)` (e.g., `Rp 5.000`) everywhere in the app.

**Chat entry and AI parsing**
- R3. Every Owner message is sent to the Parser Agent with a prompt that asks it to return `is_transaction` (boolean) plus a list of zero or more **entries**. Each entry carries its own fields: `amount` (integer rupiah), `direction` (`expense` or `income`, independent per entry — a single message may mix both, e.g., "dapet 500rb trus beli baju 200rb"), `category` (exactly one value from the fixed list in R11, matching the entry's direction), `date` (ISO date in Asia/Jakarta; defaults to today if absent), `description` (short free-text, derived from that item). A single chat message can therefore produce zero, one, or multiple Ledger rows of mixed direction.
- R3a. Multi-item messages — expense, income, or mixed — split into one Ledger row per item. Quantity shorthand follows the rule "N × item @ price" → N identical rows (e.g., "beli 2 nasi @25rb" = two rows at Rp 25.000, not one row at Rp 50.000). The chat confirmation bubble summarizes all created rows together (e.g., "✓ Logged 2 items: Rp 25.000 Makanan, Rp 5.000 Makanan").
- R4. The system must understand Indonesian shorthand for amounts: "5rb" = 5000, "5k" = 5000, "500rb" = 500000, "1jt" = 1000000, "1,5jt" = 1500000. Digit-only amounts ("5000") also work. These transformations happen via prompt instructions to the Parser Agent; the app does not implement parallel regex parsing.
- R5. The system must understand relative dates in Bahasa: "kemarin" = yesterday, "tadi pagi"/"barusan"/"tadi" = today, "minggu lalu" = 7 days ago, and explicit dates ("22 April") when given. All relative-date resolution uses Asia/Jakarta as the reference timezone. If no date is mentioned, today (Jakarta) is used.
- R6. If the Parser Agent returns `is_transaction = false`, no Ledger row is created and a short reply is shown in chat explaining nothing was logged. If the message reads as transactional but lacks an amount ("abis beli batagor"), the Parser Agent returns `is_transaction = false` with a clarifying reply asking for the amount (e.g., "Berapa harganya?"); no row is created.
- R7. If the Parser Agent returns malformed output or the request fails (including timeouts), the app replies in chat with an error bubble ("Gagal mencatat, coba lagi.") and does **not** create a Ledger row. The Owner's original message is preserved in the chat stream either way. Detailed timeout / retry / rate-limit handling is a planning concern (see Deferred to Planning).

**Ledger storage and display**
- R8. Each confirmed transaction becomes one row in the Ledger with these visible fields: date, description, amount (with sign), category, and a reference back to the original chat message.
- R9. The Ledger screen is a plain reverse-chronological list of all transactions. No monthly totals, no category breakdown, no charts in v1. Each row is tappable to edit.
- R10. Editing a row updates it in place. Fields that can be edited: amount, direction, category, date, description. The category dropdown shows only the expense categories when direction = expense, and only the income categories when direction = income; switching direction clears the category and forces re-selection. Deletion is available from the edit view; deleting a row leaves the original chat message bubble in place but replaces the confirmation bubble's content with "(entry dihapus)" so the chat history stays intact.

**Categories (fixed list)**
- R11. The category list is hardcoded in v1 and **final**:
  - **Expense categories:** Makanan & Minuman, Transport, Belanja, Hiburan, Tagihan, Kesehatan, Lainnya.
  - **Income categories:** Gaji, Lainnya (Income).
  - The list is identical for every chat message; Parser Agent must pick exactly one per entry.

**Access and deployment**
- R12. The app is deployed to a VPS with a real HTTPS URL. Access is gated by a single-user password login (one hardcoded email + password, or a single-field password page). No signup, no password reset, no session management features beyond "logged in / logged out."
- R13. The app is usable from a mobile browser. The Chat screen specifically must be comfortable to type into on a phone (input field always visible above the keyboard, messages scroll naturally).

---

## Acceptance Examples

- AE1. **Covers R3, R4, R5.** Given the Owner is logged in, when they send "kemarin beli bensin 50rb", then a Ledger row is created with amount = 50000, direction = expense, category = Transport, date = yesterday, description = "bensin", and a confirmation bubble appears in chat.
- AE2. **Covers R3, R4.** Given the Owner sends "gajian 10jt masuk", then a Ledger row is created with amount = 10000000, direction = income, category = Gaji, date = today.
- AE3. **Covers R6.** Given the Owner sends "halo apa kabar", then no Ledger row is created and the system replies with a short note that nothing was logged.
- AE4. **Covers R9, R10.** Given a Ledger row has category "Lainnya" that the Owner wants to change to "Makanan & Minuman", when the Owner taps the row and picks the new category, then the row persists with the new category and the confirmation bubble in chat updates to match.
- AE5. **Covers R7.** Given the Parser Agent returns invalid JSON or times out, then no Ledger row is created and the chat shows an error bubble; the Owner's original message remains visible in the chat stream.
- AE6. **Covers R3, R3a.** Given the Owner sends "beli nasi 25rb sama es teh 5rb", then two Ledger rows are created (amount 25000 / Makanan & Minuman / "nasi"; amount 5000 / Makanan & Minuman / "es teh") and a single confirmation bubble summarizes both.
- AE7. **Covers R3, R3a.** Given the Owner sends "beli 2 nasi @25rb", then two Ledger rows are created at Rp 25.000 each (not one row at Rp 50.000).
- AE8. **Covers R3, R3a.** Given the Owner sends "dapet transfer 500rb trus langsung beli baju 200rb", then two Ledger rows are created: one income row of Rp 500.000 (Lainnya-Income) and one expense row of Rp 200.000 (Belanja).
- AE9. **Covers R6.** Given the Owner sends "abis beli batagor" (no amount), then no Ledger row is created and the chat replies asking "Berapa harganya?".

---

## Success Criteria

- **Human outcome:** The Owner can log any given expense or income in under 5 seconds from opening the app to seeing the confirmation bubble (excluding network latency to Claude). After one month of real use, the Owner has a Ledger with >80% of entries needing zero correction — where "needing correction" means the Owner opened the inline editor (F3) and changed at least one of amount, direction, category, or date, for any reason. Entries the Owner leaves untouched count as correct regardless of whether the description prose is perfect.
- **Handoff quality:** A downstream implementer (human or `ce-plan` agent) can read this document and build v1 without needing to invent: the screen inventory, the AI's job, the category list, what to do with non-transaction messages, or how corrections work. Remaining invention is confined to technical structure (schema, prompt text, controller layout, deploy config).

---

## Scope Boundaries

**Not in v1 (deliberate exclusions):**
- Multiple users, family accounts, or public signup.
- Actual WhatsApp integration (Business API, Twilio, Fonnte). The chat surface is WhatsApp-*styled* web UI only.
- Transfers between accounts / wallets / banks, and any double-entry bookkeeping.
- Monthly summaries, category totals, charts, pie charts, trend lines, budget alerts.
- Editable / user-defined categories, category merge/rename/split.
- Attachments (receipt photos, OCR).
- Bank/e-wallet sync, CSV import, CSV export, any third-party data source.
- Recurring transactions ("subscription Netflix 150rb/bulan").
- Multi-currency. v1 is IDR only.
- Undo beyond editing/deleting individual rows. No bulk operations.
- Push notifications, reminders to log expenses, streaks.

---

## Key Decisions

- **Web app styled like WhatsApp, not real WhatsApp**: Keeps deployment simple (Rails + Kamal), avoids Meta/Twilio/Fonnte API surface, and the chat feel is what matters — not the transport.
- **Single fixed category list, no user-editable categories**: Keeps the AI prompt small, ensures consistent totals later (if/when we add totals), and avoids the common mess of "Jajan" vs "Jajanan" as different categories.
- **Log-first, tap-to-edit correction model** (not "AI asks to confirm"): Preserves the speed that makes chat entry attractive. Confirmation-every-time turns every fuzzy message into a 2-step ordeal.
- **Ledger is a plain list in v1, no summaries**: The Owner chose this deliberately. Insight features (monthly totals, breakdowns) are a clear v2 direction and deferred, not rejected.
- **Claude Haiku as the parser, via RubyLLM**: Fast and cheap enough for per-message calls. RubyLLM is the Rails-idiomatic integration path.
- **VPS + simple password gate, not Rails full auth**: Single user; Rails 8 auth generator would be ceremony for one hardcoded account. Can be upgraded later if scope ever expands.
- **Multi-item messages split into separate rows** (not one combined row): Preserves granularity for editing and future category breakdowns. Costs a slightly more complex AI contract (list of entries, not a single entry) — worth it.
- **Plain-list ledger is an accepted bet, not a settled outcome**: v1 ships with no totals or breakdowns on purpose. The risk is the Owner stops opening the app because the ledger gives nothing back after a month of logging. If that happens, v2 adds running totals / monthly summary; the bet is that raw capture alone is worth it as a 4-6 week experiment.

---

## Dependencies / Assumptions

- Anthropic API key available and funded. Target model is the current Claude Haiku 4.5 (exact dated slug to be confirmed against Anthropic's model list at implementation time — the bare alias `claude-haiku-4-5` may or may not resolve; a dated slug like `claude-haiku-4-5-YYYYMMDD` is the safe pin). Per-message cost is assumed negligible at personal-use volume (tens of messages per day).
- Ruby on Rails (Rails 8.x assumed, greenfield) and the `ruby_llm` gem are the stack. Version pin and Rails 8 compatibility verified by running `bundle install` and a smoke test during planning; if `ruby_llm` is unusable, a direct Anthropic SDK or Faraday wrapper is the fallback.
- A VPS is available (DigitalOcean / Hetzner / Biznet Gio-class) and the Owner is willing to deploy via Kamal. If not, deployment falls back to the localhost-only option, which degrades the "log on the go" use case.
- **Timezone:** Asia/Jakarta. Set via Rails `config.time_zone = "Asia/Jakarta"`; all relative-date parsing (R5) and row timestamps resolve in this zone.
- **Credential recovery:** If the Owner forgets/mistypes the login password, recovery is via SSH into the VPS and re-setting the credential + `kamal deploy`. This is accepted as the single recovery path — no in-app password reset.
- Assumed parsing accuracy of Claude Haiku on Bahasa shorthand ("5rb", "1,5jt", "kemarin") is high enough that R4/R5 can be satisfied by prompt alone without custom regex. If accuracy is insufficient during planning/testing, a deterministic pre-parse step may be added — this is a planning decision, not a brainstorm one.
- Assumed that typing one message and waiting ~1-3s for Haiku is acceptable latency. If not, streaming or optimistic UI becomes necessary — out of v1 unless measured to be a problem.

---

## Outstanding Questions

### Resolve Before Planning

*(None — all blocking product decisions are resolved.)*

### Deferred to Planning

- [Affects R3, R7][Technical] Exact `ruby_llm` configuration, prompt text, and structured-output strategy (tool call vs. JSON schema vs. plain JSON in text). Best decided against the live RubyLLM API during planning. Includes timeout, 429/rate-limit backoff, and the `is_transaction = true` with empty-entries-list edge case.
- [Affects R12][Technical] Exact auth implementation: `has_secure_password` on a one-row User vs. a plaintext credential in `Rails.application.credentials` behind a single-field password page. Both trivially acceptable; pick during planning.
- [Affects R12][Technical] Abuse protections: rate-limit login attempts + cap daily chat endpoint calls so a password leak can't burn Anthropic credits unboundedly. `rack-attack` or Rails 8's built-in rate-limiter on `Session#create` and `Messages#create`.
- [Affects R13][Needs research] Whether the chat input stays above the mobile keyboard reliably across iOS Safari / Android Chrome with common CSS patterns, or whether `interactive-widget=resizes-content` / `100dvh` tricks are needed. Verify with a real device during planning.
- [Affects R2, R8][Technical] Data model: one `transactions` table plus a `chat_messages` table with a foreign key, or fold both into one table. Planning decision.
- [Affects F1][UX] The chat bubble state while the Parser Agent is thinking: spinner bubble, typing-indicator, or instant optimistic confirmation that's replaced on response. Pick during view implementation.
- [Affects F3, R9, R2][UX] Tappable affordance for bubbles and rows — how the UI signals "tap to edit" without a WhatsApp precedent (chevron, hover style, small edit icon). Pick during view implementation.
- [Affects F3, R10][UX] When a row is edited from the Ledger side (not via the chat bubble), does the corresponding chat confirmation bubble re-render to match? Recommended yes (single source of truth via Turbo Stream update), but confirm during planning.
- [Affects R3][Reliability] Ordering guarantee when the user sends N messages in rapid succession while Parser Agent calls are still in flight. Simplest answer: serialize via a per-user background queue. Decide during planning.
- [Affects R3, R8][Privacy] Anthropic data-retention policy review for financial content transmitted to the API. Also: configure `config.filter_parameters` so chat messages don't leak into Rails logs.
- [Affects R12][Ops] Kamal secrets file for the Anthropic API key — kept out of source control, rotated if compromised.

---

## Next Steps

-> `/ce-plan` for structured implementation planning.
