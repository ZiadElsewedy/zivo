# expenses — feature map

> Append-only spending log with a running wallet balance and custom categories.
> Hue: **Solar** (see the design system).

## Start here

- `presentation/pages/expenses_list_page.dart` — the spend log + wallet balance.
- `presentation/pages/expense_capture_page.dart` — add an expense (`amount_keypad.dart`,
  `category_chips.dart`).
- Widgets: `add_category_sheet.dart`, `wallet_balance_sheet.dart`, `category_hue_colors.dart`,
  `category_icons.dart`.
- Today glance: [`home/presentation/widgets/spending_glance.dart`](../home/presentation/widgets/spending_glance.dart).

## Repositories (three)

- **`ExpenseRepository`** (`AppScope.expenses`) — the append-only log.
- **`WalletRepository`** (`AppScope.wallet`, nullable) — running balance.
- **`CategoryRepository`** (`AppScope.expenseCategories`, nullable) — custom categories.

Each has `firestore_*` + `in_memory_*` impls in `data/`. Cross-cutting logic:
`domain/expenses_service.dart`.

## Domain

`expense.dart`, `expense_category.dart`, `wallet.dart`. Money formatting lives in
[`core/util/money.dart`](../../core/util/money.dart).

## Gotchas

- **Categories carry a `CategoryIcon`, never an emoji.** The identity spec rules emoji out
  (§4, §8), so a category stores a *semantic* icon name (`iconId` in Firestore) that
  `category_icons.dart` resolves to a stroked Lucide glyph via `AppIcons` — the same shape
  as `category_hue_colors.dart` for hues. Nothing in `lib/` imports the icon package except
  `AppIcons`; keep it that way. Documents saved before this change carry `emoji` instead,
  and `FirestoreCategoryRepository` reads them through `categoryIconFromLegacyEmoji`;
  that path and the rules test's `emoji`-shaped invalid payload can go once no live
  account holds a pre-migration category.

- The **manual UI** treats the log as append-only — corrections are new entries. But the
  repository (`update`/`remove`) and [`firestore.rules`](../../../firestore.rules) both support
  in-place edit **and** delete, and the **AI** now uses them (confirm-gated —
  [ADR-005](../../../docs/DECISIONS/ADR-005-ai-edit-delete-expenses.md), via
  `functions/ai/store.js`). The wallet balance is derived from the log, so it stays correct after
  an edit/delete. If you add manual edit/delete affordances, recompute the wallet from the log.
