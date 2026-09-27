# Palmy — API operation catalog

Generated from [openapi.json](openapi.json). All routes are relative to `/api/v1`.

| Method | Route | Purpose | Requirement |
|---|---|---|---|
| GET | `/me` | Read authenticated user | FR-20 |
| PATCH | `/me` | Update own display profile | FR-20 |
| POST | `/households` | Create household and initial owner | FR-20 |
| GET | `/households/{household_id}` | Read household | FR-20 |
| GET | `/households/{household_id}/members` | List household members | FR-20 |
| PATCH | `/households/{household_id}/members/{member_id}` | Update member or revoke access | FR-20 |
| POST | `/households/{household_id}/invitations` | Invite household member | FR-20 |
| GET | `/households/{household_id}/invitations` | List invitations | FR-20 |
| POST | `/invitations/acceptances` | Accept invitation for authenticated intended identity | FR-20 |
| GET | `/households/{household_id}/settings` | Read household preferences | FR-21 |
| PATCH | `/households/{household_id}/settings` | Update household preferences | FR-21 |
| GET | `/households/{household_id}/dashboard` | Read home summary | FR-02 |
| GET | `/households/{household_id}/wallets` | List wallets | FR-03 |
| POST | `/households/{household_id}/wallets` | Create Wallet | FR-03 |
| GET | `/households/{household_id}/wallets/{wallet_id}` | Get Wallet | FR-03 |
| PATCH | `/households/{household_id}/wallets/{wallet_id}` | Update Wallet | FR-03 |
| POST | `/households/{household_id}/wallets/{wallet_id}/adjustments` | Post audited balance adjustment | FR-03 |
| POST | `/households/{household_id}/transfers` | Post atomic wallet transfer | FR-04 |
| POST | `/households/{household_id}/wallets/{wallet_id}/payments` | Pay credit wallet outstanding | FR-04 |
| GET | `/households/{household_id}/categories` | List categories | FR-08 |
| POST | `/households/{household_id}/categories` | Create Category | FR-08 |
| GET | `/households/{household_id}/categories/{category_id}` | Get Category | FR-08 |
| PATCH | `/households/{household_id}/categories/{category_id}` | Update Category | FR-08 |
| GET | `/households/{household_id}/budgets` | List reporting-period budgets | FR-08 |
| POST | `/households/{household_id}/budgets` | Create explicit reporting-period budget | FR-08 |
| PATCH | `/households/{household_id}/budgets/{budget_id}` | Replace category budget limits atomically | FR-08 |
| GET | `/households/{household_id}/transactions` | Search and filter financial history | FR-06 |
| POST | `/households/{household_id}/transactions` | Post reviewed income or expense | FR-05 |
| GET | `/households/{household_id}/transactions/{transaction_id}` | Read financial operation | FR-05 |
| POST | `/households/{household_id}/transactions/{transaction_id}/corrections` | Reverse and replace posted transaction | FR-05 |
| POST | `/households/{household_id}/transactions/{transaction_id}/reversals` | Reverse posted transaction | FR-05 |
| POST | `/households/{household_id}/transactions/{transaction_id}/drafts` | Copy transaction into unsaved review draft | FR-05 |
| GET | `/households/{household_id}/debts` | List debts | FR-09 |
| POST | `/households/{household_id}/debts` | Create Debt | FR-09 |
| GET | `/households/{household_id}/debts/{debt_id}` | Get Debt | FR-09 |
| PATCH | `/households/{household_id}/debts/{debt_id}` | Update Debt | FR-09 |
| GET | `/households/{household_id}/debts/{debt_id}/payments` | List debt payments | FR-09 |
| POST | `/households/{household_id}/debts/{debt_id}/payments` | Post principal settlement | FR-09 |
| POST | `/households/{household_id}/debts/{debt_id}/payments/{payment_id}/reversals` | Reverse debt settlement and linked journal | FR-09 |
| GET | `/households/{household_id}/goals` | List goals | FR-10 |
| POST | `/households/{household_id}/goals` | Create Goal | FR-10 |
| GET | `/households/{household_id}/goals/{goal_id}` | Get Goal | FR-10 |
| PATCH | `/households/{household_id}/goals/{goal_id}` | Update Goal | FR-10 |
| GET | `/households/{household_id}/goals/{goal_id}/movements` | List goal cash reservations | FR-10 |
| POST | `/households/{household_id}/goals/{goal_id}/movements` | Reserve or release goal funds | FR-10 |
| POST | `/households/{household_id}/goals/{goal_id}/asset-links` | Link whole holding to goal | FR-10 |
| DELETE | `/households/{household_id}/goals/{goal_id}/asset-links/{link_id}` | Unlink holding from goal | FR-10 |
| GET | `/households/{household_id}/assets` | List assets | FR-11 |
| POST | `/households/{household_id}/assets` | Create Asset | FR-11 |
| GET | `/households/{household_id}/assets/{asset_id}` | Get Asset | FR-11 |
| PATCH | `/households/{household_id}/assets/{asset_id}` | Update Asset | FR-11 |
| GET | `/households/{household_id}/assets/{asset_id}/trades` | List asset operations | FR-11 |
| POST | `/households/{household_id}/assets/{asset_id}/trades` | Record purchase sale income or unit correction | FR-11 |
| GET | `/households/{household_id}/assets/{asset_id}/quotes` | Read valuation history | FR-11 |
| POST | `/households/{household_id}/assets/{asset_id}/quotes` | Record manual quote | FR-11 |
| POST | `/households/{household_id}/assets/{asset_id}/trades/{trade_id}/reversals` | Reverse asset trade and linked journal | FR-11 |
| POST | `/households/{household_id}/assets/{asset_id}/quote-refreshes` | Refresh provider quote | FR-11 |
| GET | `/households/{household_id}/asset-instruments` | Search provider instrument catalog | FR-11 |
| GET | `/households/{household_id}/asset-performance` | Read labeled portfolio performance | FR-11 |
| GET | `/households/{household_id}/asset-quotes` | Read latest holding quotes | FR-11 |
| POST | `/households/{household_id}/asset-quotes/batches` | Post manual quote batch atomically | FR-11 |
| GET | `/households/{household_id}/allocation-plans` | List allocation-plans | FR-12 |
| POST | `/households/{household_id}/allocation-plans` | Create AllocationPlan | FR-12 |
| GET | `/households/{household_id}/allocation-plans/{plan_id}` | Get AllocationPlan | FR-12 |
| PATCH | `/households/{household_id}/allocation-plans/{plan_id}` | Update AllocationPlan | FR-12 |
| POST | `/households/{household_id}/allocation-plans/{plan_id}/previews` | Preview allocation amounts and budget impact | FR-12 |
| POST | `/households/{household_id}/allocation-plans/{plan_id}/applications` | Apply confirmed allocation to period budgets | FR-12 |
| GET | `/households/{household_id}/recurring-templates` | List recurring-templates | FR-13 |
| POST | `/households/{household_id}/recurring-templates` | Create RecurringTemplate | FR-13 |
| GET | `/households/{household_id}/recurring-templates/{template_id}` | Get RecurringTemplate | FR-13 |
| PATCH | `/households/{household_id}/recurring-templates/{template_id}` | Update RecurringTemplate | FR-13 |
| POST | `/households/{household_id}/recurring-templates/{template_id}/occurrences` | Record reviewed recurring occurrence | FR-13 |
| GET | `/households/{household_id}/recurring-templates/{template_id}/occurrences` | List recorded occurrences | FR-13 |
| GET | `/households/{household_id}/shopping-sections` | List shopping-sections | FR-16 |
| POST | `/households/{household_id}/shopping-sections` | Create ShoppingSection | FR-16 |
| GET | `/households/{household_id}/shopping-sections/{section_id}` | Get ShoppingSection | FR-16 |
| PATCH | `/households/{household_id}/shopping-sections/{section_id}` | Update ShoppingSection | FR-16 |
| GET | `/households/{household_id}/shopping-items` | List shopping-items | FR-16 |
| POST | `/households/{household_id}/shopping-items` | Create ShoppingItem | FR-16 |
| GET | `/households/{household_id}/shopping-items/{item_id}` | Get ShoppingItem | FR-16 |
| PATCH | `/households/{household_id}/shopping-items/{item_id}` | Update ShoppingItem | FR-16 |
| GET | `/households/{household_id}/shopping-routines` | List shopping-routines | FR-16 |
| POST | `/households/{household_id}/shopping-routines` | Create ShoppingRoutine | FR-16 |
| GET | `/households/{household_id}/shopping-routines/{routine_id}` | Get ShoppingRoutine | FR-16 |
| PATCH | `/households/{household_id}/shopping-routines/{routine_id}` | Update ShoppingRoutine | FR-16 |
| GET | `/households/{household_id}/shopping-purchases` | Read purchases and price history | FR-16 |
| POST | `/households/{household_id}/shopping-purchases` | Check out selected grocery items | FR-16 |
| POST | `/households/{household_id}/shopping-purchases/{purchase_id}/corrections` | Replace purchase snapshot and financial effect | FR-16 |
| GET | `/households/{household_id}/calendar-categories` | List calendar-categories | FR-17 |
| POST | `/households/{household_id}/calendar-categories` | Create CalendarCategory | FR-17 |
| GET | `/households/{household_id}/calendar-categories/{category_id}` | Get CalendarCategory | FR-17 |
| PATCH | `/households/{household_id}/calendar-categories/{category_id}` | Update CalendarCategory | FR-17 |
| GET | `/households/{household_id}/calendar-items` | List calendar-items | FR-17 |
| POST | `/households/{household_id}/calendar-items` | Create CalendarItem | FR-17 |
| GET | `/households/{household_id}/calendar-items/{item_id}` | Get CalendarItem | FR-17 |
| PATCH | `/households/{household_id}/calendar-items/{item_id}` | Update CalendarItem | FR-17 |
| PUT | `/households/{household_id}/calendar-items/{item_id}/completion` | Set task occurrence completion | FR-17 |
| POST | `/households/{household_id}/calendar-feeds` | Create read-only calendar feed | FR-17 |
| DELETE | `/households/{household_id}/calendar-feeds/{feed_id}` | Revoke calendar feed | FR-17 |
| GET | `/households/{household_id}/maintenance-items` | List maintenance-items | FR-18 |
| POST | `/households/{household_id}/maintenance-items` | Create MaintenanceItem | FR-18 |
| GET | `/households/{household_id}/maintenance-items/{item_id}` | Get MaintenanceItem | FR-18 |
| PATCH | `/households/{household_id}/maintenance-items/{item_id}` | Update MaintenanceItem | FR-18 |
| GET | `/households/{household_id}/maintenance-items/{item_id}/services` | List service history | FR-18 |
| POST | `/households/{household_id}/maintenance-items/{item_id}/services` | Record service and optional expense | FR-18 |
| POST | `/households/{household_id}/maintenance-items/{item_id}/services/{service_id}/corrections` | Replace service and linked financial effect | FR-18 |
| GET | `/households/{household_id}/important-links` | List important-links | FR-19 |
| POST | `/households/{household_id}/important-links` | Create ImportantLink | FR-19 |
| GET | `/households/{household_id}/important-links/{link_id}` | Get ImportantLink | FR-19 |
| PATCH | `/households/{household_id}/important-links/{link_id}` | Update ImportantLink | FR-19 |
| POST | `/households/{household_id}/calculations/loan` | Calculate loan | FR-15 |
| POST | `/households/{household_id}/calculations/takeover` | Calculate takeover | FR-15 |
| POST | `/households/{household_id}/calculations/education` | Calculate education | FR-15 |
| GET | `/households/{household_id}/calculator-scenarios` | List saved scenarios | FR-15 |
| POST | `/households/{household_id}/calculator-scenarios` | Save independently computed scenario | FR-15 |
| GET | `/households/{household_id}/reports/cashflow` | Read cashflow report | FR-14 |
| GET | `/households/{household_id}/reports/net-worth` | Read net-worth report | FR-14 |
| GET | `/households/{household_id}/reports/breakdown` | Read breakdown report | FR-14 |
| POST | `/households/{household_id}/files` | Create short-lived private upload URL | FR-22 |
| GET | `/households/{household_id}/files/{file_id}` | Read scan status | FR-22 |
| POST | `/households/{household_id}/files/{file_id}/completions` | Confirm upload and enqueue file scan | FR-22 |
| POST | `/households/{household_id}/imports` | Validate uploaded import into preview | FR-22 |
| GET | `/households/{household_id}/imports/{job_id}/rows` | Read row-level validation | FR-22 |
| POST | `/households/{household_id}/imports/{job_id}/commits` | Commit selected valid preview rows atomically | FR-22 |
| POST | `/households/{household_id}/exports` | Generate selective household export | FR-22 |
| GET | `/households/{household_id}/jobs/{job_id}` | Read asynchronous job | FR-22 |
| POST | `/households/{household_id}/ocr-jobs` | Extract review drafts from uploaded receipt files | FR-07 |
| POST | `/households/{household_id}/transaction-parses` | Parse text into uncommitted draft | FR-07 |
| POST | `/households/{household_id}/insights` | Generate period insight | FR-02 |
| GET | `/households/{household_id}/notifications` | Read current user inbox | FR-02 |
| PATCH | `/households/{household_id}/notifications/{notification_id}` | Change notification read state | FR-02 |
| POST | `/households/{household_id}/push-subscriptions` | Register authorized push subscription | FR-02 |
| DELETE | `/households/{household_id}/push-subscriptions/{subscription_id}` | Revoke push subscription | FR-02 |
| POST | `/households/{household_id}/step-up-grants` | Verify PIN or identity assertion | FR-21 |
| PUT | `/households/{household_id}/pin` | Set PIN after identity reauthentication | FR-21 |
| POST | `/households/{household_id}/destructive-plans` | Preview reset or deletion impact | FR-21 |
| POST | `/households/{household_id}/destructive-commits` | Queue explicitly confirmed reset or deletion | FR-21 |
| GET | `/households/{household_id}/integrations/google-sheets` | Read Sheets connection | FR-22 |
| DELETE | `/households/{household_id}/integrations/google-sheets` | Revoke Sheets integration and provider token | FR-22 |
| POST | `/households/{household_id}/integrations/google-sheets/authorizations` | Begin authorized OAuth connection | FR-22 |
| POST | `/households/{household_id}/integrations/google-sheets/callbacks` | Complete OAuth code exchange | FR-22 |
| GET | `/households/{household_id}/affiliate` | Read own affiliate account | FR-23 |
| GET | `/households/{household_id}/affiliate/commissions` | Read own commission ledger | FR-23 |
| GET | `/households/{household_id}/affiliate/payout-destinations` | Read masked payout destinations | FR-23 |
| POST | `/households/{household_id}/affiliate/payout-destinations` | Create encrypted payout destination | FR-23 |
| GET | `/households/{household_id}/affiliate/payouts` | Read own payout history | FR-23 |
| POST | `/households/{household_id}/affiliate/payouts` | Request eligible commission withdrawal | FR-23 |
| POST | `/households/{household_id}/affiliate/promotions` | Submit own promotion URL for review | FR-23 |
| GET | `/feedback` | Read public feature board | FR-24 |
| POST | `/households/{household_id}/feedback` | Publish product suggestion | FR-24 |
| PUT | `/feedback/{post_id}/vote` | Set current user vote | FR-24 |
| DELETE | `/feedback/{post_id}/vote` | Remove current user vote | FR-24 |
| GET | `/help` | List published help articles | FR-24 |
| GET | `/help/{slug}` | Read versioned help article | FR-24 |
