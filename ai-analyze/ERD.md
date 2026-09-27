# Palmy — entity relationship diagrams

Proposed model; all in-scope household domains are represented. Each tenant child uses a composite `(household_id, referenced_id)` foreign key. IDs and optionality are fully specified in [schema.sql](schema.sql) and [database-dictionary.md](database-dictionary.md).

The complete 62-table diagram is [palmy-erd.mmd](palmy-erd.mmd). These smaller views omit repeated tenant and audit links for readability. They do not imply a different schema.

## Household and finance

```mermaid
erDiagram
    users ||--o{ memberships : joins
    households ||--o{ memberships : has
    households ||--o{ wallets : owns
    households ||--o{ categories : organizes
    ledger_accounts ||--o| wallets : backs
    ledger_accounts ||--o{ journal_lines : receives
    journal_entries ||--|{ journal_lines : balances
    journal_entries ||--o{ entry_allocations : analyzes
    categories ||--o{ entry_allocations : classifies
    memberships |o--o{ entry_allocations : attributes
    categories |o--o{ categories : parent
    budget_periods ||--o{ budget_limits : contains
    categories ||--o{ budget_limits : limits
    wallets ||--o{ wallet_category_rules : permits
    categories ||--o{ wallet_category_rules : restricts
    merchants |o--o{ journal_entries : identifies
```

A posted journal requires at least two lines; the diagram's one-or-more relationship is tightened by the balance trigger. Wallets map one-to-one to accounts by a unique constraint. Category hierarchy is limited to one child level.

## Debt, goals and investments

```mermaid
erDiagram
    ledger_accounts ||--o{ debts : tracks
    debts ||--o{ debt_payments : settles
    journal_entries ||--o| debt_payments : posts
    goals ||--o{ goal_movements : reserves
    wallets ||--o{ goal_movements : funds
    goals ||--o{ goal_asset_links : combines
    asset_holdings ||--o| goal_asset_links : assigned
    asset_holdings ||--o{ asset_trades : changes
    asset_holdings ||--o{ asset_quotes : valued
    ledger_accounts ||--o| asset_holdings : carries_cost
    journal_entries |o--o{ asset_trades : posts
    allocation_plans ||--o{ allocation_items : targets
    categories |o--o{ allocation_items : maps
    goals |o--o{ allocation_items : maps
    recurring_templates ||--o{ recurring_occurrences : executes
    journal_entries ||--o{ recurring_occurrences : records
```

Cash reservations are labels over wallet money. A goal's linked holding contributes market value to progress without another household asset. An asset trade may omit a journal for a unit correction; purchased/sold money-bearing trades require one through the command service.

## Shopping, calendar and maintenance

```mermaid
erDiagram
    shopping_sections ||--o{ shopping_items : groups
    shopping_sections |o--o{ shopping_routines : repeats
    shopping_purchases ||--o{ shopping_purchase_items : snapshots
    shopping_items |o--o{ shopping_purchase_items : originates
    journal_entries |o--o{ shopping_purchases : posts
    calendar_categories ||--o{ calendar_items : groups
    calendar_items ||--o{ calendar_exceptions : overrides
    calendar_items ||--o{ calendar_reminders : reminds
    calendar_items |o--o{ maintenance_items : schedules
    maintenance_items ||--o{ service_records : serviced
    journal_entries |o--o{ service_records : posts
    files ||--o{ file_links : attaches
    journal_entries |o--o{ file_links : includes
    service_records |o--o{ file_links : includes
    calendar_items |o--o{ file_links : includes
    asset_trades |o--o{ file_links : includes
```

Each file link points to exactly one typed domain resource. Service and purchase record-only mode has no journal; a recorded cost has a linked journal. A purchase needs at least one line through the checkout service even though a header can exist transiently within its transaction.

## Platform and affiliate

```mermaid
erDiagram
    users ||--o{ notifications : receives
    users ||--o{ device_subscriptions : registers
    users ||--o{ pin_credentials : verifies
    users ||--o{ step_up_grants : authenticates
    users ||--o| affiliate_accounts : owns
    affiliate_accounts ||--o{ affiliate_commissions : earns
    affiliate_accounts ||--o{ payout_destinations : configures
    affiliate_accounts ||--o{ payout_requests : requests
    payout_destinations ||--o{ payout_requests : receives
    affiliate_accounts ||--o{ promotion_submissions : submits
    files |o--o{ jobs : input_or_output
    jobs ||--o{ import_rows : validates
    journal_entries |o--o{ import_rows : commits
    users ||--o{ feedback_posts : authors
    feedback_posts ||--o{ feedback_votes : receives
    users ||--o{ feedback_votes : votes
    households ||--o{ audit_events : audits
    households ||--o{ outbox_events : delivers
    households ||--o{ idempotency_keys : deduplicates
```

Notifications, affiliate records and security grants are additionally user-scoped. Public feedback reads use a narrow projection; tenant data does not become public merely because a post is public. Help articles are global versioned content. Calendar-feed and OAuth credentials remain private and are omitted from export models.
