# Palmy — database column dictionary

62 tables. Generated from the same definitions as schema.sql and palmy-erd.mmd.

All tables have UUID id, created_at, updated_at and optimistic version. Tenant tables additionally have household_id and UNIQUE(household_id, id). These common columns are omitted below. Composite tenant foreign keys use ON DELETE RESTRICT.

## users

Identity provider subject and public profile.

| Column | SQL type and constraint |
|---|---|
| auth_subject | `text NOT NULL UNIQUE` |
| display_name | `text NOT NULL` |
| locale | `text NOT NULL DEFAULT 'id-ID'` |

Additional checks: none.
Unique keys: primary ID and tenant composite key.
Mutability: versioned; posted journal/lines have additional immutability triggers.

## households

Tenant root.

| Column | SQL type and constraint |
|---|---|
| name | `text NOT NULL CHECK(length(trim(name)) BETWEEN 1 AND 120)` |
| timezone | `text NOT NULL DEFAULT 'Asia/Jakarta'` |
| base_currency | `char(3) NOT NULL DEFAULT 'IDR' CHECK(base_currency='IDR')` |

Additional checks: none.
Unique keys: primary ID and tenant composite key.
Mutability: versioned; posted journal/lines have additional immutability triggers.

## memberships

Household membership and role.

| Column | SQL type and constraint |
|---|---|
| user_id | `uuid NOT NULL REFERENCES palmy.users(id)` |
| role | `text NOT NULL CHECK(role IN ('owner','member'))` |
| status | `text NOT NULL DEFAULT 'active' CHECK(status IN ('active','revoked'))` |
| display_name | `text NOT NULL` |

Additional checks: none.
Unique keys: `household_id,user_id`.
Mutability: versioned; posted journal/lines have additional immutability triggers.

## invitations

Expiring single-use member invitations.

| Column | SQL type and constraint |
|---|---|
| email_ciphertext | `bytea NOT NULL` |
| token_digest | `text NOT NULL UNIQUE` |
| expires_at | `timestamptz NOT NULL` |
| accepted_by | `uuid REFERENCES palmy.users(id)` |
| accepted_at | `timestamptz` |
| revoked_at | `timestamptz` |
| invited_by | `uuid NOT NULL REFERENCES palmy.users(id)` |

Additional checks: none.
Unique keys: primary ID and tenant composite key.
Mutability: versioned; posted journal/lines have additional immutability triggers.

## household_settings

Reporting and display preferences.

| Column | SQL type and constraint |
|---|---|
| cycle_start_day | `smallint NOT NULL DEFAULT 1 CHECK(cycle_start_day BETWEEN 1 AND 28)` |
| display_currency | `char(3) NOT NULL DEFAULT 'IDR'` |
| display_rate | `palmy.rate NOT NULL DEFAULT 1` |
| rate_as_of | `timestamptz` |
| default_split_bps | `smallint NOT NULL DEFAULT 5000 CHECK(default_split_bps BETWEEN 0 AND 10000)` |
| weather_location_label | `text` |
| weather_latitude | `numeric(8,5)` |
| weather_longitude | `numeric(8,5)` |
| photo_file_id | uuid nullable; composite FK → files |

Additional checks: none.
Unique keys: `household_id`.
Mutability: versioned; posted journal/lines have additional immutability triggers.

## ledger_accounts

Chart of accounts, debit-positive.

| Column | SQL type and constraint |
|---|---|
| name | `text NOT NULL` |
| kind | `text NOT NULL CHECK(kind IN ('asset','liability','income','expense','equity'))` |
| system_code | `text` |
| include_in_net_worth | `boolean NOT NULL DEFAULT true` |
| archived_at | `timestamptz` |

Additional checks: none.
Unique keys: `household_id,system_code`.
Mutability: versioned; posted journal/lines have additional immutability triggers.

## wallets

Cash, bank, credit and external cash containers.

| Column | SQL type and constraint |
|---|---|
| name | `text NOT NULL CHECK(length(trim(name)) BETWEEN 1 AND 120)` |
| kind | `text NOT NULL CHECK(kind IN ('cash','bank','ewallet','credit','external'))` |
| icon | `text` |
| credit_limit | `palmy.money CHECK(credit_limit>=0)` |
| is_primary | `boolean NOT NULL DEFAULT false` |
| sort_order | `integer NOT NULL DEFAULT 0` |
| archived_at | `timestamptz` |
| account_id | uuid NOT NULL; composite FK → ledger_accounts |
| owner_member_id | uuid nullable; composite FK → memberships |

Additional checks: `(kind='credit') = (credit_limit IS NOT NULL)`.
Unique keys: `household_id,account_id`.
Mutability: versioned; posted journal/lines have additional immutability triggers.

## categories

Income/expense categories with at most one child level.

| Column | SQL type and constraint |
|---|---|
| name | `text NOT NULL CHECK(length(trim(name)) BETWEEN 1 AND 120)` |
| direction | `text NOT NULL CHECK(direction IN ('income','expense'))` |
| icon | `text` |
| color | `text` |
| default_need | `text CHECK(default_need IN ('need','want'))` |
| due_day | `smallint CHECK(due_day BETWEEN 1 AND 31)` |
| sort_order | `integer NOT NULL DEFAULT 0` |
| archived_at | `timestamptz` |
| parent_id | uuid nullable; composite FK → categories |
| account_id | uuid NOT NULL; composite FK → ledger_accounts |

Additional checks: `parent_id IS NULL OR parent_id<>id`.
Unique keys: primary ID and tenant composite key.
Mutability: versioned; posted journal/lines have additional immutability triggers.

## wallet_category_rules

Explicit allowed wallet-category relation.

| Column | SQL type and constraint |
|---|---|
| wallet_id | uuid NOT NULL; composite FK → wallets |
| category_id | uuid NOT NULL; composite FK → categories |

Additional checks: none.
Unique keys: `household_id,wallet_id,category_id`.
Mutability: versioned; posted journal/lines have additional immutability triggers.

## budget_periods

Materialized reporting periods.

| Column | SQL type and constraint |
|---|---|
| starts_on | `date NOT NULL` |
| ends_on | `date NOT NULL` |

Additional checks: `ends_on>=starts_on`.
Unique keys: `household_id,starts_on,ends_on`.
Mutability: versioned; posted journal/lines have additional immutability triggers.

## budget_limits

Category limit for a reporting period.

| Column | SQL type and constraint |
|---|---|
| amount | `palmy.money NOT NULL CHECK(amount>=0)` |
| period_id | uuid NOT NULL; composite FK → budget_periods |
| category_id | uuid NOT NULL; composite FK → categories |

Additional checks: none.
Unique keys: `household_id,period_id,category_id`.
Mutability: versioned; posted journal/lines have additional immutability triggers.

## merchants

Household-local merchant names.

| Column | SQL type and constraint |
|---|---|
| name | `text NOT NULL CHECK(length(trim(name))>0)` |

Additional checks: none.
Unique keys: `household_id,name`.
Mutability: versioned; posted journal/lines have additional immutability triggers.

## journal_entries

Atomic financial operation header; posted entries immutable.

| Column | SQL type and constraint |
|---|---|
| kind | `text NOT NULL CHECK(kind IN ('income','expense','transfer','credit_payment','opening','adjustment','debt_origin','debt_payment','goal_transfer','asset_purchase','asset_sale','dividend','grocery_checkout','maintenance_service','reversal'))` |
| state | `text NOT NULL DEFAULT 'draft' CHECK(state IN ('draft','posted'))` |
| effective_on | `date NOT NULL` |
| effective_time | `time` |
| description | `text NOT NULL DEFAULT ''` |
| amount | `palmy.money NOT NULL CHECK(amount>0)` |
| fee | `palmy.money NOT NULL DEFAULT 0 CHECK(fee>=0)` |
| source | `text NOT NULL DEFAULT 'manual' CHECK(source IN ('manual','ai','ocr','import','recurring','system'))` |
| created_by | `uuid NOT NULL REFERENCES palmy.users(id)` |
| posted_at | `timestamptz` |
| wallet_id | uuid nullable; composite FK → wallets |
| destination_wallet_id | uuid nullable; composite FK → wallets |
| merchant_id | uuid nullable; composite FK → merchants |
| reverses_entry_id | uuid nullable; composite FK → journal_entries |

Additional checks: `wallet_id IS NULL OR destination_wallet_id IS NULL OR wallet_id<>destination_wallet_id`; `(state='posted')=(posted_at IS NOT NULL)`.
Unique keys: `household_id,reverses_entry_id`.
Mutability: versioned; posted journal/lines have additional immutability triggers.

## journal_lines

Exact signed debit/credit postings.

| Column | SQL type and constraint |
|---|---|
| amount | `palmy.money NOT NULL CHECK(amount<>0)` |
| memo | `text` |
| entry_id | uuid NOT NULL; composite FK → journal_entries |
| account_id | uuid NOT NULL; composite FK → ledger_accounts |

Additional checks: none.
Unique keys: primary ID and tenant composite key.
Mutability: versioned; posted journal/lines have additional immutability triggers.

## entry_allocations

Category/member analysis, separate from ledger balances.

| Column | SQL type and constraint |
|---|---|
| amount | `palmy.money NOT NULL CHECK(amount>0)` |
| need | `text CHECK(need IN ('need','want'))` |
| counts_in_budget | `boolean NOT NULL DEFAULT true` |
| entry_id | uuid NOT NULL; composite FK → journal_entries |
| category_id | uuid NOT NULL; composite FK → categories |
| member_id | uuid nullable; composite FK → memberships |

Additional checks: none.
Unique keys: primary ID and tenant composite key.
Mutability: versioned; posted journal/lines have additional immutability triggers.

## debts

Borrowed/lent principal with optional opening ledger effect.

| Column | SQL type and constraint |
|---|---|
| name | `text NOT NULL` |
| direction | `text NOT NULL CHECK(direction IN ('payable','receivable'))` |
| origin | `text NOT NULL CHECK(origin IN ('cash','goods','prior'))` |
| original_principal | `palmy.money NOT NULL CHECK(original_principal>0)` |
| annual_rate | `numeric(9,6) CHECK(annual_rate>=0)` |
| term_months | `integer CHECK(term_months>0)` |
| opened_on | `date NOT NULL` |
| due_on | `date` |
| phone_ciphertext | `bytea` |
| notes | `text` |
| include_in_net_worth | `boolean NOT NULL DEFAULT true` |
| archived_at | `timestamptz` |
| account_id | uuid NOT NULL; composite FK → ledger_accounts |
| origin_entry_id | uuid nullable; composite FK → journal_entries |
| member_id | uuid nullable; composite FK → memberships |

Additional checks: none.
Unique keys: primary ID and tenant composite key.
Mutability: versioned; posted journal/lines have additional immutability triggers.

## debt_payments

Principal/interest/fee breakdown for settlement.

| Column | SQL type and constraint |
|---|---|
| principal | `palmy.money NOT NULL CHECK(principal>0)` |
| interest | `palmy.money NOT NULL DEFAULT 0 CHECK(interest>=0)` |
| fee | `palmy.money NOT NULL DEFAULT 0 CHECK(fee>=0)` |
| paid_on | `date NOT NULL` |
| debt_id | uuid NOT NULL; composite FK → debts |
| entry_id | uuid NOT NULL; composite FK → journal_entries |
| reverses_payment_id | uuid nullable; composite FK → debt_payments |

Additional checks: none.
Unique keys: `household_id,entry_id`; `household_id,reverses_payment_id`.
Mutability: append-only; update/delete rejected by trigger.

## goals

Savings objective; value derived from reservations and linked holdings.

| Column | SQL type and constraint |
|---|---|
| name | `text NOT NULL` |
| type | `text NOT NULL CHECK(type IN ('holiday','emergency','vehicle','wedding','property','education','retirement','other'))` |
| target_amount | `palmy.money NOT NULL CHECK(target_amount>0)` |
| target_on | `date` |
| notes | `text` |
| include_in_net_worth | `boolean NOT NULL DEFAULT true` |
| archived_at | `timestamptz` |
| default_wallet_id | uuid nullable; composite FK → wallets |

Additional checks: none.
Unique keys: primary ID and tenant composite key.
Mutability: versioned; posted journal/lines have additional immutability triggers.

## goal_movements

Signed cash reservation changes; not additional money.

| Column | SQL type and constraint |
|---|---|
| amount | `palmy.money NOT NULL CHECK(amount<>0)` |
| kind | `text NOT NULL CHECK(kind IN ('reserve','release'))` |
| effective_on | `date NOT NULL` |
| note | `text` |
| goal_id | uuid NOT NULL; composite FK → goals |
| wallet_id | uuid NOT NULL; composite FK → wallets |
| entry_id | uuid nullable; composite FK → journal_entries |

Additional checks: `(kind='reserve' AND amount>0) OR (kind='release' AND amount<0)`.
Unique keys: primary ID and tenant composite key.
Mutability: append-only; update/delete rejected by trigger.

## asset_holdings

Investment class and remaining position read model.

| Column | SQL type and constraint |
|---|---|
| name | `text NOT NULL` |
| asset_class | `text NOT NULL CHECK(asset_class IN ('gold','silver','dinar','fx','stock','etf','crypto','bond','deposit','mutual_fund','property','other'))` |
| symbol | `text` |
| broker | `text` |
| quote_currency | `char(3) NOT NULL DEFAULT 'IDR'` |
| unit | `text NOT NULL` |
| annual_rate | `numeric(9,6)` |
| matures_on | `date` |
| include_in_net_worth | `boolean NOT NULL DEFAULT true` |
| archived_at | `timestamptz` |
| account_id | uuid NOT NULL; composite FK → ledger_accounts |

Additional checks: none.
Unique keys: `household_id,account_id`.
Mutability: versioned; posted journal/lines have additional immutability triggers.

## asset_trades

Purchase, sale, income or audited quantity correction.

| Column | SQL type and constraint |
|---|---|
| kind | `text NOT NULL CHECK(kind IN ('buy','sell','dividend','unit_correction','reversal'))` |
| quantity_delta | `palmy.quantity NOT NULL` |
| unit_price | `palmy.money CHECK(unit_price>=0)` |
| gross_amount | `palmy.money NOT NULL CHECK(gross_amount>=0)` |
| fee | `palmy.money NOT NULL DEFAULT 0 CHECK(fee>=0)` |
| cost_basis_delta | `palmy.money NOT NULL` |
| effective_on | `date NOT NULL` |
| reason | `text` |
| holding_id | uuid NOT NULL; composite FK → asset_holdings |
| entry_id | uuid nullable; composite FK → journal_entries |
| reverses_trade_id | uuid nullable; composite FK → asset_trades |

Additional checks: `(kind='buy' AND quantity_delta>0 AND cost_basis_delta>=0) OR (kind='sell' AND quantity_delta<0 AND cost_basis_delta<=0) OR (kind='dividend' AND quantity_delta=0 AND cost_basis_delta=0) OR (kind='unit_correction' AND cost_basis_delta=0 AND reason IS NOT NULL) OR (kind='reversal' AND reverses_trade_id IS NOT NULL)`; `(kind='reversal')=(reverses_trade_id IS NOT NULL)`.
Unique keys: `household_id,reverses_trade_id`.
Mutability: append-only; update/delete rejected by trigger.

## asset_quotes

Timestamped valuation provenance, never overwrite history.

| Column | SQL type and constraint |
|---|---|
| unit_price | `palmy.money NOT NULL CHECK(unit_price>=0)` |
| currency | `char(3) NOT NULL` |
| base_conversion_rate | `palmy.rate NOT NULL CHECK(base_conversion_rate>0)` |
| quoted_at | `timestamptz NOT NULL` |
| source | `text NOT NULL` |
| is_manual | `boolean NOT NULL DEFAULT false` |
| holding_id | uuid NOT NULL; composite FK → asset_holdings |

Additional checks: none.
Unique keys: primary ID and tenant composite key.
Mutability: append-only; update/delete rejected by trigger.

## goal_asset_links

Exclusive whole-holding link to prevent duplicate goal progress.

| Column | SQL type and constraint |
|---|---|
| goal_id | uuid NOT NULL; composite FK → goals |
| holding_id | uuid NOT NULL; composite FK → asset_holdings |

Additional checks: none.
Unique keys: `household_id,holding_id`.
Mutability: versioned; posted journal/lines have additional immutability triggers.

## allocation_plans

Income or portfolio allocation plan.

| Column | SQL type and constraint |
|---|---|
| name | `text NOT NULL` |
| kind | `text NOT NULL CHECK(kind IN ('income','portfolio'))` |
| income_amount | `palmy.money CHECK(income_amount>=0)` |
| state | `text NOT NULL DEFAULT 'draft' CHECK(state IN ('draft','active','archived'))` |

Additional checks: none.
Unique keys: primary ID and tenant composite key.
Mutability: versioned; posted journal/lines have additional immutability triggers.

## allocation_items

Basis-point targets and optional budget/goal mapping.

| Column | SQL type and constraint |
|---|---|
| name | `text NOT NULL` |
| basis_points | `integer NOT NULL CHECK(basis_points BETWEEN 0 AND 10000)` |
| asset_class | `text` |
| sort_order | `integer NOT NULL DEFAULT 0` |
| plan_id | uuid NOT NULL; composite FK → allocation_plans |
| category_id | uuid nullable; composite FK → categories |
| goal_id | uuid nullable; composite FK → goals |

Additional checks: `num_nonnulls(category_id,goal_id,asset_class)<=1`.
Unique keys: primary ID and tenant composite key.
Mutability: versioned; posted journal/lines have additional immutability triggers.

## recurring_templates

Reviewable recurring financial draft.

| Column | SQL type and constraint |
|---|---|
| name | `text NOT NULL` |
| frequency | `text NOT NULL CHECK(frequency IN ('monthly','yearly'))` |
| day_of_month | `smallint NOT NULL CHECK(day_of_month BETWEEN 1 AND 31)` |
| month_of_year | `smallint CHECK(month_of_year BETWEEN 1 AND 12)` |
| amount | `palmy.money NOT NULL CHECK(amount>0)` |
| fee | `palmy.money NOT NULL DEFAULT 0 CHECK(fee>=0)` |
| direction | `text NOT NULL CHECK(direction IN ('income','expense'))` |
| paused_at | `timestamptz` |
| wallet_id | uuid NOT NULL; composite FK → wallets |
| category_id | uuid nullable; composite FK → categories |
| member_id | uuid nullable; composite FK → memberships |
| debt_id | uuid nullable; composite FK → debts |
| goal_id | uuid nullable; composite FK → goals |
| holding_id | uuid nullable; composite FK → asset_holdings |

Additional checks: `(frequency='yearly')=(month_of_year IS NOT NULL)`; `num_nonnulls(debt_id,goal_id,holding_id)<=1`.
Unique keys: primary ID and tenant composite key.
Mutability: versioned; posted journal/lines have additional immutability triggers.

## recurring_occurrences

Exactly one posted occurrence per due date.

| Column | SQL type and constraint |
|---|---|
| due_on | `date NOT NULL` |
| template_id | uuid NOT NULL; composite FK → recurring_templates |
| entry_id | uuid NOT NULL; composite FK → journal_entries |

Additional checks: none.
Unique keys: `household_id,template_id,due_on`.
Mutability: append-only; update/delete rejected by trigger.

## shopping_sections

Organized grocery lists.

| Column | SQL type and constraint |
|---|---|
| name | `text NOT NULL` |
| sort_order | `integer NOT NULL DEFAULT 0` |
| archived_at | `timestamptz` |

Additional checks: none.
Unique keys: primary ID and tenant composite key.
Mutability: versioned; posted journal/lines have additional immutability triggers.

## shopping_items

Current grocery checklist item.

| Column | SQL type and constraint |
|---|---|
| name | `text NOT NULL` |
| quantity | `palmy.quantity NOT NULL CHECK(quantity>0)` |
| unit | `text` |
| unit_price | `palmy.money NOT NULL CHECK(unit_price>=0)` |
| selected | `boolean NOT NULL DEFAULT false` |
| sort_order | `integer NOT NULL DEFAULT 0` |
| archived_at | `timestamptz` |
| section_id | uuid NOT NULL; composite FK → shopping_sections |

Additional checks: none.
Unique keys: primary ID and tenant composite key.
Mutability: versioned; posted journal/lines have additional immutability triggers.

## shopping_purchases

Immutable checkout record with optional financial posting.

| Column | SQL type and constraint |
|---|---|
| purchased_on | `date NOT NULL` |
| total | `palmy.money NOT NULL CHECK(total>=0)` |
| record_only | `boolean NOT NULL DEFAULT false` |
| entry_id | uuid nullable; composite FK → journal_entries |
| merchant_id | uuid nullable; composite FK → merchants |
| replaces_purchase_id | uuid nullable; composite FK → shopping_purchases |

Additional checks: `record_only=(entry_id IS NULL)`.
Unique keys: `household_id,replaces_purchase_id`.
Mutability: append-only; update/delete rejected by trigger.

## shopping_purchase_items

Snapshot lines preserve price history.

| Column | SQL type and constraint |
|---|---|
| name | `text NOT NULL` |
| quantity | `palmy.quantity NOT NULL CHECK(quantity>0)` |
| unit_price | `palmy.money NOT NULL CHECK(unit_price>=0)` |
| line_total | `palmy.money NOT NULL CHECK(line_total>=0)` |
| purchase_id | uuid NOT NULL; composite FK → shopping_purchases |
| shopping_item_id | uuid nullable; composite FK → shopping_items |

Additional checks: none.
Unique keys: primary ID and tenant composite key.
Mutability: append-only; update/delete rejected by trigger.

## shopping_routines

Recurring household needs.

| Column | SQL type and constraint |
|---|---|
| name | `text NOT NULL` |
| interval_days | `integer NOT NULL CHECK(interval_days>0)` |
| quantity | `palmy.quantity NOT NULL CHECK(quantity>0)` |
| estimated_price | `palmy.money CHECK(estimated_price>=0)` |
| next_due_on | `date` |
| paused_at | `timestamptz` |
| section_id | uuid nullable; composite FK → shopping_sections |

Additional checks: none.
Unique keys: primary ID and tenant composite key.
Mutability: versioned; posted journal/lines have additional immutability triggers.

## calendar_categories

Event or checklist grouping.

| Column | SQL type and constraint |
|---|---|
| name | `text NOT NULL` |
| kind | `text NOT NULL CHECK(kind IN ('event','checklist'))` |
| color | `text` |
| sort_order | `integer NOT NULL DEFAULT 0` |
| archived_at | `timestamptz` |

Additional checks: none.
Unique keys: primary ID and tenant composite key.
Mutability: versioned; posted journal/lines have additional immutability triggers.

## calendar_items

Date-only or timed event/task series.

| Column | SQL type and constraint |
|---|---|
| title | `text NOT NULL CHECK(length(trim(title))>0)` |
| kind | `text NOT NULL CHECK(kind IN ('event','task'))` |
| starts_on | `date` |
| ends_on | `date` |
| local_time | `time` |
| timezone | `text NOT NULL` |
| assignee_label | `text` |
| rrule | `text` |
| completed_at | `timestamptz` |
| sort_order | `integer NOT NULL DEFAULT 0` |
| archived_at | `timestamptz` |
| category_id | uuid NOT NULL; composite FK → calendar_categories |
| assignee_member_id | uuid nullable; composite FK → memberships |

Additional checks: `ends_on IS NULL OR (starts_on IS NOT NULL AND ends_on>=starts_on)`; `kind='task' OR starts_on IS NOT NULL`; `local_time IS NULL OR starts_on IS NOT NULL`.
Unique keys: primary ID and tenant composite key.
Mutability: versioned; posted journal/lines have additional immutability triggers.

## calendar_exceptions

Completion, reschedule or cancellation of one recurring occurrence.

| Column | SQL type and constraint |
|---|---|
| occurrence_on | `date NOT NULL` |
| override_on | `date` |
| cancelled | `boolean NOT NULL DEFAULT false` |
| completed_at | `timestamptz` |
| item_id | uuid NOT NULL; composite FK → calendar_items |

Additional checks: none.
Unique keys: `household_id,item_id,occurrence_on`.
Mutability: versioned; posted journal/lines have additional immutability triggers.

## calendar_reminders

Offset and delivery-channel preferences.

| Column | SQL type and constraint |
|---|---|
| offset_minutes | `integer NOT NULL CHECK(offset_minutes>=0)` |
| channel | `text NOT NULL CHECK(channel IN ('in_app','push'))` |
| item_id | uuid NOT NULL; composite FK → calendar_items |

Additional checks: none.
Unique keys: `household_id,item_id,offset_minutes,channel`.
Mutability: versioned; posted journal/lines have additional immutability triggers.

## calendar_feeds

Revocable hashed read-only calendar tokens.

| Column | SQL type and constraint |
|---|---|
| token_digest | `text NOT NULL UNIQUE` |
| revoked_at | `timestamptz` |
| last_used_at | `timestamptz` |
| created_by | `uuid NOT NULL REFERENCES palmy.users(id)` |

Additional checks: none.
Unique keys: primary ID and tenant composite key.
Mutability: versioned; posted journal/lines have additional immutability triggers.

## maintenance_items

Vehicle, home or electronic equipment.

| Column | SQL type and constraint |
|---|---|
| name | `text NOT NULL` |
| kind | `text NOT NULL CHECK(kind IN ('vehicle','home','electronic'))` |
| subtype | `text` |
| interval_days | `integer CHECK(interval_days>0)` |
| next_due_on | `date` |
| notes | `text` |
| archived_at | `timestamptz` |
| calendar_item_id | uuid nullable; composite FK → calendar_items |

Additional checks: none.
Unique keys: primary ID and tenant composite key.
Mutability: versioned; posted journal/lines have additional immutability triggers.

## service_records

Service history and optional expense.

| Column | SQL type and constraint |
|---|---|
| description | `text NOT NULL` |
| serviced_on | `date NOT NULL` |
| cost | `palmy.money NOT NULL CHECK(cost>=0)` |
| record_only | `boolean NOT NULL DEFAULT false` |
| next_due_on | `date` |
| notes | `text` |
| maintenance_item_id | uuid NOT NULL; composite FK → maintenance_items |
| entry_id | uuid nullable; composite FK → journal_entries |
| replaces_service_id | uuid nullable; composite FK → service_records |

Additional checks: `record_only=(entry_id IS NULL)`.
Unique keys: `household_id,replaces_service_id`.
Mutability: append-only; update/delete rejected by trigger.

## important_links

PIN-gated useful URLs.

| Column | SQL type and constraint |
|---|---|
| name | `text NOT NULL CHECK(length(trim(name))>0)` |
| url | `text NOT NULL CHECK(url ~ '^https?://[^[:space:]]+$')` |
| sort_order | `integer NOT NULL DEFAULT 0` |
| archived_at | `timestamptz` |

Additional checks: none.
Unique keys: primary ID and tenant composite key.
Mutability: versioned; posted journal/lines have additional immutability triggers.

## calculator_scenarios

Versioned calculation inputs and immutable result snapshot.

| Column | SQL type and constraint |
|---|---|
| name | `text NOT NULL` |
| type | `text NOT NULL CHECK(type IN ('loan','takeover','education'))` |
| formula_version | `text NOT NULL` |
| inputs | `jsonb NOT NULL CHECK(jsonb_typeof(inputs)='object')` |
| result | `jsonb NOT NULL CHECK(jsonb_typeof(result)='object')` |

Additional checks: none.
Unique keys: primary ID and tenant composite key.
Mutability: versioned; posted journal/lines have additional immutability triggers.

## files

Private object storage metadata and scanning state.

| Column | SQL type and constraint |
|---|---|
| storage_key | `text NOT NULL UNIQUE` |
| mime_type | `text NOT NULL` |
| byte_size | `bigint NOT NULL CHECK(byte_size BETWEEN 1 AND 20971520)` |
| sha 256 | `text NOT NULL CHECK(length(sha256)=64)` |
| state | `text NOT NULL CHECK(state IN ('pending','clean','rejected','deleted'))` |
| uploaded_by | `uuid NOT NULL REFERENCES palmy.users(id)` |
| expires_at | `timestamptz` |

Additional checks: none.
Unique keys: primary ID and tenant composite key.
Mutability: versioned; posted journal/lines have additional immutability triggers.

## file_links

Typed attachment link, exactly one resource.

| Column | SQL type and constraint |
|---|---|
| file_id | uuid NOT NULL; composite FK → files |
| entry_id | uuid nullable; composite FK → journal_entries |
| service_id | uuid nullable; composite FK → service_records |
| asset_trade_id | uuid nullable; composite FK → asset_trades |
| calendar_item_id | uuid nullable; composite FK → calendar_items |

Additional checks: `num_nonnulls(entry_id,service_id,asset_trade_id,calendar_item_id)=1`.
Unique keys: primary ID and tenant composite key.
Mutability: versioned; posted journal/lines have additional immutability triggers.

## jobs

Async imports, exports, OCR and insight work.

| Column | SQL type and constraint |
|---|---|
| kind | `text NOT NULL CHECK(kind IN ('import','export','ocr','insight','sheets_sync','file_scan','reset','delete_account','quote_refresh'))` |
| state | `text NOT NULL DEFAULT 'queued' CHECK(state IN ('queued','running','review','succeeded','failed','cancelled'))` |
| requested_by | `uuid NOT NULL REFERENCES palmy.users(id)` |
| options | `jsonb NOT NULL DEFAULT '{}'` |
| result | `jsonb NOT NULL DEFAULT '{}'` |
| error_code | `text` |
| attempts | `integer NOT NULL DEFAULT 0 CHECK(attempts>=0)` |
| started_at | `timestamptz` |
| completed_at | `timestamptz` |
| input_file_id | uuid nullable; composite FK → files |
| output_file_id | uuid nullable; composite FK → files |

Additional checks: none.
Unique keys: primary ID and tenant composite key.
Mutability: versioned; posted journal/lines have additional immutability triggers.

## import_rows

Preview, row errors and duplicate identity.

| Column | SQL type and constraint |
|---|---|
| row_number | `integer NOT NULL CHECK(row_number>0)` |
| source_fingerprint | `text NOT NULL` |
| normalized_data | `jsonb NOT NULL` |
| errors | `jsonb NOT NULL DEFAULT '[]'` |
| state | `text NOT NULL DEFAULT 'pending' CHECK(state IN ('pending','valid','invalid','committed','skipped'))` |
| job_id | uuid NOT NULL; composite FK → jobs |
| entry_id | uuid nullable; composite FK → journal_entries |

Additional checks: none.
Unique keys: `household_id,job_id,row_number`.
Mutability: versioned; posted journal/lines have additional immutability triggers.

## integrations

External integration consent and secret reference.

| Column | SQL type and constraint |
|---|---|
| provider | `text NOT NULL CHECK(provider='google_sheets')` |
| state | `text NOT NULL CHECK(state IN ('connected','revoked','expired'))` |
| scopes | `text[] NOT NULL` |
| credential_secret_ref | `text` |
| external_resource_id | `text` |
| connected_by | `uuid NOT NULL REFERENCES palmy.users(id)` |
| revoked_at | `timestamptz` |

Additional checks: none.
Unique keys: `household_id,provider`.
Mutability: versioned; posted journal/lines have additional immutability triggers.

## pin_credentials

PIN verifier only; secret values never exported.

| Column | SQL type and constraint |
|---|---|
| user_id | `uuid NOT NULL REFERENCES palmy.users(id)` |
| argon 2id_verifier | `text NOT NULL` |
| failed_attempts | `integer NOT NULL DEFAULT 0 CHECK(failed_attempts>=0)` |
| locked_until | `timestamptz` |

Additional checks: none.
Unique keys: `household_id,user_id`.
Mutability: versioned; posted journal/lines have additional immutability triggers.

## step_up_grants

Short-lived scoped authorization after identity/PIN verification.

| Column | SQL type and constraint |
|---|---|
| user_id | `uuid NOT NULL REFERENCES palmy.users(id)` |
| token_digest | `text NOT NULL UNIQUE` |
| scope | `text NOT NULL CHECK(scope IN ('links','reset','delete_account','payout_destination','pin_change','calendar_feed'))` |
| expires_at | `timestamptz NOT NULL` |
| used_at | `timestamptz` |

Additional checks: none.
Unique keys: primary ID and tenant composite key.
Mutability: versioned; posted journal/lines have additional immutability triggers.

## destructive_plans

Expiring reviewable lifecycle plan.

| Column | SQL type and constraint |
|---|---|
| user_id | `uuid NOT NULL REFERENCES palmy.users(id)` |
| scope | `text NOT NULL CHECK(scope IN ('wallet','household','account'))` |
| target_id | `uuid NOT NULL` |
| plan_hash | `text NOT NULL` |
| impact | `jsonb NOT NULL` |
| confirmation_phrase | `text NOT NULL` |
| expires_at | `timestamptz NOT NULL` |
| consumed_at | `timestamptz` |

Additional checks: none.
Unique keys: primary ID and tenant composite key.
Mutability: versioned; posted journal/lines have additional immutability triggers.

## device_subscriptions

Optional push endpoint and encrypted keys.

| Column | SQL type and constraint |
|---|---|
| user_id | `uuid NOT NULL REFERENCES palmy.users(id)` |
| endpoint_digest | `text NOT NULL` |
| endpoint_ciphertext | `bytea NOT NULL` |
| keys_ciphertext | `bytea NOT NULL` |
| revoked_at | `timestamptz` |

Additional checks: none.
Unique keys: `household_id,user_id,endpoint_digest`.
Mutability: versioned; posted journal/lines have additional immutability triggers.

## notifications

Per-user inbox with business-event deduplication.

| Column | SQL type and constraint |
|---|---|
| user_id | `uuid NOT NULL REFERENCES palmy.users(id)` |
| type | `text NOT NULL` |
| title | `text NOT NULL` |
| body | `text` |
| target_path | `text` |
| dedupe_key | `text NOT NULL` |
| read_at | `timestamptz` |

Additional checks: none.
Unique keys: `household_id,user_id,dedupe_key`.
Mutability: versioned; posted journal/lines have additional immutability triggers.

## affiliate_accounts

Affiliate identity owned by one user.

| Column | SQL type and constraint |
|---|---|
| user_id | `uuid NOT NULL REFERENCES palmy.users(id)` |
| referral_code | `text NOT NULL UNIQUE` |
| status | `text NOT NULL CHECK(status IN ('active','suspended'))` |

Additional checks: none.
Unique keys: `user_id`.
Mutability: versioned; posted journal/lines have additional immutability triggers.

## affiliate_commissions

Append-only earned/reversed commissions.

| Column | SQL type and constraint |
|---|---|
| source_event_id | `text NOT NULL UNIQUE` |
| amount | `palmy.money NOT NULL CHECK(amount<>0)` |
| eligible_at | `timestamptz NOT NULL` |
| reason | `text NOT NULL` |
| affiliate_id | uuid NOT NULL; composite FK → affiliate_accounts |

Additional checks: none.
Unique keys: primary ID and tenant composite key.
Mutability: append-only; update/delete rejected by trigger.

## payout_destinations

Encrypted bank details plus safe display suffix.

| Column | SQL type and constraint |
|---|---|
| bank_code | `text NOT NULL` |
| account_ciphertext | `bytea NOT NULL` |
| account_last4 | `char(4) NOT NULL` |
| holder_ciphertext | `bytea NOT NULL` |
| verified_at | `timestamptz` |
| archived_at | `timestamptz` |
| affiliate_id | uuid NOT NULL; composite FK → affiliate_accounts |

Additional checks: none.
Unique keys: primary ID and tenant composite key.
Mutability: versioned; posted journal/lines have additional immutability triggers.

## payout_requests

Reserved commission withdrawal state machine.

| Column | SQL type and constraint |
|---|---|
| amount | `palmy.money NOT NULL CHECK(amount>=50000)` |
| state | `text NOT NULL DEFAULT 'requested' CHECK(state IN ('requested','processing','paid','failed','cancelled'))` |
| provider_reference | `text UNIQUE` |
| paid_at | `timestamptz` |
| affiliate_id | uuid NOT NULL; composite FK → affiliate_accounts |
| destination_id | uuid NOT NULL; composite FK → payout_destinations |

Additional checks: none.
Unique keys: primary ID and tenant composite key.
Mutability: versioned; posted journal/lines have additional immutability triggers.

## promotion_submissions

Affiliate campaign URL and review status.

| Column | SQL type and constraint |
|---|---|
| url | `text NOT NULL CHECK(url ~ '^https?://[^[:space:]]+$')` |
| state | `text NOT NULL DEFAULT 'pending' CHECK(state IN ('pending','approved','rejected'))` |
| affiliate_id | uuid NOT NULL; composite FK → affiliate_accounts |

Additional checks: none.
Unique keys: primary ID and tenant composite key.
Mutability: versioned; posted journal/lines have additional immutability triggers.

## feedback_posts

Public product suggestion without household financial fields.

| Column | SQL type and constraint |
|---|---|
| author_id | `uuid NOT NULL REFERENCES palmy.users(id)` |
| topic | `text NOT NULL` |
| title | `text NOT NULL` |
| body | `text NOT NULL` |
| status | `text NOT NULL DEFAULT 'queued' CHECK(status IN ('queued','in_progress','released','declined'))` |
| is_public | `boolean NOT NULL DEFAULT true` |

Additional checks: none.
Unique keys: primary ID and tenant composite key.
Mutability: versioned; posted journal/lines have additional immutability triggers.

## feedback_votes

One vote per user and post.

| Column | SQL type and constraint |
|---|---|
| user_id | `uuid NOT NULL REFERENCES palmy.users(id)` |
| post_id | `uuid NOT NULL REFERENCES palmy.feedback_posts(id)` |

Additional checks: none.
Unique keys: `user_id,post_id`.
Mutability: versioned; posted journal/lines have additional immutability triggers.

## help_articles

Versioned global FAQ, help and legal-link metadata.

| Column | SQL type and constraint |
|---|---|
| slug | `text NOT NULL UNIQUE` |
| locale | `text NOT NULL` |
| title | `text NOT NULL` |
| body | `text NOT NULL` |
| product_version | `text NOT NULL` |
| published_at | `timestamptz` |

Additional checks: none.
Unique keys: primary ID and tenant composite key.
Mutability: versioned; posted journal/lines have additional immutability triggers.

## idempotency_keys

Atomic request-result record scoped to user and route.

| Column | SQL type and constraint |
|---|---|
| user_id | `uuid NOT NULL REFERENCES palmy.users(id)` |
| route | `text NOT NULL` |
| key | `text NOT NULL` |
| request_hash | `text NOT NULL` |
| response_status | `integer` |
| response_body | `jsonb` |
| expires_at | `timestamptz NOT NULL` |

Additional checks: none.
Unique keys: `household_id,user_id,route,key`.
Mutability: versioned; posted journal/lines have additional immutability triggers.

## audit_events

Append-only trace without secrets or sensitive descriptions.

| Column | SQL type and constraint |
|---|---|
| actor_id | `uuid REFERENCES palmy.users(id)` |
| action | `text NOT NULL` |
| resource_type | `text NOT NULL` |
| resource_id | `uuid` |
| request_id | `uuid NOT NULL` |
| metadata | `jsonb NOT NULL DEFAULT '{}'` |

Additional checks: none.
Unique keys: primary ID and tenant composite key.
Mutability: append-only; update/delete rejected by trigger.

## outbox_events

Transactional domain-event delivery.

| Column | SQL type and constraint |
|---|---|
| event_type | `text NOT NULL` |
| aggregate_id | `uuid NOT NULL` |
| dedupe_key | `text NOT NULL` |
| payload | `jsonb NOT NULL` |
| available_at | `timestamptz NOT NULL DEFAULT now()` |
| delivered_at | `timestamptz` |
| attempts | `integer NOT NULL DEFAULT 0 CHECK(attempts>=0)` |

Additional checks: none.
Unique keys: `household_id,dedupe_key`.
Mutability: versioned; posted journal/lines have additional immutability triggers.
