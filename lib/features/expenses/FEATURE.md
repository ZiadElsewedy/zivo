# expenses — feature map

> Append-only spending log with a running wallet balance and custom categories.
> Hue: **Solar** (see the design system).

## Start here

- `presentation/pages/expenses_list_page.dart` — the spend log + wallet balance.
- `presentation/pages/expense_capture_page.dart` — add an expense (`amount_keypad.dart`,
  `category_chips.dart`).
- Widgets: `add_category_sheet.dart`, `wallet_balance_sheet.dart`, `category_hue_colors.dart`.
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

- The log is **append-only** — corrections are new entries, not edits/deletes; the wallet
  balance is derived from the log. Don't add in-place mutation of past entries.
