-- Palmy proposed schema v1; PostgreSQL 17+. New database only.
-- The migration role owns this schema; runtime role must not own tables or bypass RLS.
BEGIN;
CREATE SCHEMA palmy;
CREATE DOMAIN palmy.money AS numeric CHECK(VALUE BETWEEN -9999999999999999.99 AND 9999999999999999.99 AND scale(VALUE)<=2);
CREATE DOMAIN palmy.quantity AS numeric CHECK(VALUE BETWEEN -999999999999999999.9999999999 AND 999999999999999999.9999999999 AND scale(VALUE)<=10);
CREATE DOMAIN palmy.rate AS numeric CHECK(VALUE>0 AND VALUE<1000000000000 AND scale(VALUE)<=10);

-- Identity provider subject and public profile
CREATE TABLE palmy.users (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  auth_subject text NOT NULL UNIQUE,
  display_name text NOT NULL,
  locale text NOT NULL DEFAULT 'id-ID',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  version bigint NOT NULL DEFAULT 1 CHECK(version>0)
);

-- Tenant root
CREATE TABLE palmy.households (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL CHECK(length(trim(name)) BETWEEN 1 AND 120),
  timezone text NOT NULL DEFAULT 'Asia/Jakarta',
  base_currency char(3) NOT NULL DEFAULT 'IDR' CHECK(base_currency='IDR'),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  version bigint NOT NULL DEFAULT 1 CHECK(version>0)
);

-- Household membership and role
CREATE TABLE palmy.memberships (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id uuid NOT NULL REFERENCES palmy.households(id),
  user_id uuid NOT NULL REFERENCES palmy.users(id),
  role text NOT NULL CHECK(role IN ('owner','member')),
  status text NOT NULL DEFAULT 'active' CHECK(status IN ('active','revoked')),
  display_name text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  version bigint NOT NULL DEFAULT 1 CHECK(version>0),
  UNIQUE(household_id,id),
  UNIQUE(household_id,user_id)
);

-- Expiring single-use member invitations
CREATE TABLE palmy.invitations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id uuid NOT NULL REFERENCES palmy.households(id),
  email_ciphertext bytea NOT NULL,
  token_digest text NOT NULL UNIQUE,
  expires_at timestamptz NOT NULL,
  accepted_by uuid REFERENCES palmy.users(id),
  accepted_at timestamptz,
  revoked_at timestamptz,
  invited_by uuid NOT NULL REFERENCES palmy.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  version bigint NOT NULL DEFAULT 1 CHECK(version>0),
  UNIQUE(household_id,id)
);

-- Reporting and display preferences
CREATE TABLE palmy.household_settings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id uuid NOT NULL REFERENCES palmy.households(id),
  cycle_start_day smallint NOT NULL DEFAULT 1 CHECK(cycle_start_day BETWEEN 1 AND 28),
  display_currency char(3) NOT NULL DEFAULT 'IDR',
  display_rate palmy.rate NOT NULL DEFAULT 1,
  rate_as_of timestamptz,
  default_split_bps smallint NOT NULL DEFAULT 5000 CHECK(default_split_bps BETWEEN 0 AND 10000),
  weather_location_label text,
  weather_latitude numeric(8,5),
  weather_longitude numeric(8,5),
  photo_file_id uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  version bigint NOT NULL DEFAULT 1 CHECK(version>0),
  UNIQUE(household_id,id),
  UNIQUE(household_id)
);

-- Chart of accounts, debit-positive
CREATE TABLE palmy.ledger_accounts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id uuid NOT NULL REFERENCES palmy.households(id),
  name text NOT NULL,
  kind text NOT NULL CHECK(kind IN ('asset','liability','income','expense','equity')),
  system_code text,
  include_in_net_worth boolean NOT NULL DEFAULT true,
  archived_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  version bigint NOT NULL DEFAULT 1 CHECK(version>0),
  UNIQUE(household_id,id),
  UNIQUE(household_id,system_code)
);

-- Cash, bank, credit and external cash containers
CREATE TABLE palmy.wallets (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id uuid NOT NULL REFERENCES palmy.households(id),
  name text NOT NULL CHECK(length(trim(name)) BETWEEN 1 AND 120),
  kind text NOT NULL CHECK(kind IN ('cash','bank','ewallet','credit','external')),
  icon text,
  credit_limit palmy.money CHECK(credit_limit>=0),
  is_primary boolean NOT NULL DEFAULT false,
  sort_order integer NOT NULL DEFAULT 0,
  archived_at timestamptz,
  account_id uuid NOT NULL,
  owner_member_id uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  version bigint NOT NULL DEFAULT 1 CHECK(version>0),
  UNIQUE(household_id,id),
  CHECK((kind='credit') = (credit_limit IS NOT NULL)),
  UNIQUE(household_id,account_id)
);

-- Income/expense categories with at most one child level
CREATE TABLE palmy.categories (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id uuid NOT NULL REFERENCES palmy.households(id),
  name text NOT NULL CHECK(length(trim(name)) BETWEEN 1 AND 120),
  direction text NOT NULL CHECK(direction IN ('income','expense')),
  icon text,
  color text,
  default_need text CHECK(default_need IN ('need','want')),
  due_day smallint CHECK(due_day BETWEEN 1 AND 31),
  sort_order integer NOT NULL DEFAULT 0,
  archived_at timestamptz,
  parent_id uuid,
  account_id uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  version bigint NOT NULL DEFAULT 1 CHECK(version>0),
  UNIQUE(household_id,id),
  CHECK(parent_id IS NULL OR parent_id<>id)
);

-- Explicit allowed wallet-category relation
CREATE TABLE palmy.wallet_category_rules (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id uuid NOT NULL REFERENCES palmy.households(id),
  wallet_id uuid NOT NULL,
  category_id uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  version bigint NOT NULL DEFAULT 1 CHECK(version>0),
  UNIQUE(household_id,id),
  UNIQUE(household_id,wallet_id,category_id)
);

-- Materialized reporting periods
CREATE TABLE palmy.budget_periods (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id uuid NOT NULL REFERENCES palmy.households(id),
  starts_on date NOT NULL,
  ends_on date NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  version bigint NOT NULL DEFAULT 1 CHECK(version>0),
  UNIQUE(household_id,id),
  CHECK(ends_on>=starts_on),
  UNIQUE(household_id,starts_on,ends_on)
);

-- Category limit for a reporting period
CREATE TABLE palmy.budget_limits (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id uuid NOT NULL REFERENCES palmy.households(id),
  amount palmy.money NOT NULL CHECK(amount>=0),
  period_id uuid NOT NULL,
  category_id uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  version bigint NOT NULL DEFAULT 1 CHECK(version>0),
  UNIQUE(household_id,id),
  UNIQUE(household_id,period_id,category_id)
);

-- Household-local merchant names
CREATE TABLE palmy.merchants (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id uuid NOT NULL REFERENCES palmy.households(id),
  name text NOT NULL CHECK(length(trim(name))>0),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  version bigint NOT NULL DEFAULT 1 CHECK(version>0),
  UNIQUE(household_id,id),
  UNIQUE(household_id,name)
);

-- Atomic financial operation header; posted entries immutable
CREATE TABLE palmy.journal_entries (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id uuid NOT NULL REFERENCES palmy.households(id),
  kind text NOT NULL CHECK(kind IN ('income','expense','transfer','credit_payment','opening','adjustment','debt_origin','debt_payment','goal_transfer','asset_purchase','asset_sale','dividend','grocery_checkout','maintenance_service','reversal')),
  state text NOT NULL DEFAULT 'draft' CHECK(state IN ('draft','posted')),
  effective_on date NOT NULL,
  effective_time time,
  description text NOT NULL DEFAULT '',
  amount palmy.money NOT NULL CHECK(amount>0),
  fee palmy.money NOT NULL DEFAULT 0 CHECK(fee>=0),
  source text NOT NULL DEFAULT 'manual' CHECK(source IN ('manual','ai','ocr','import','recurring','system')),
  created_by uuid NOT NULL REFERENCES palmy.users(id),
  posted_at timestamptz,
  wallet_id uuid,
  destination_wallet_id uuid,
  merchant_id uuid,
  reverses_entry_id uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  version bigint NOT NULL DEFAULT 1 CHECK(version>0),
  UNIQUE(household_id,id),
  CHECK(wallet_id IS NULL OR destination_wallet_id IS NULL OR wallet_id<>destination_wallet_id),
  CHECK((state='posted')=(posted_at IS NOT NULL)),
  UNIQUE(household_id,reverses_entry_id)
);

-- Exact signed debit/credit postings
CREATE TABLE palmy.journal_lines (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id uuid NOT NULL REFERENCES palmy.households(id),
  amount palmy.money NOT NULL CHECK(amount<>0),
  memo text,
  entry_id uuid NOT NULL,
  account_id uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  version bigint NOT NULL DEFAULT 1 CHECK(version>0),
  UNIQUE(household_id,id)
);

-- Category/member analysis, separate from ledger balances
CREATE TABLE palmy.entry_allocations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id uuid NOT NULL REFERENCES palmy.households(id),
  amount palmy.money NOT NULL CHECK(amount>0),
  need text CHECK(need IN ('need','want')),
  counts_in_budget boolean NOT NULL DEFAULT true,
  entry_id uuid NOT NULL,
  category_id uuid NOT NULL,
  member_id uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  version bigint NOT NULL DEFAULT 1 CHECK(version>0),
  UNIQUE(household_id,id)
);

-- Borrowed/lent principal with optional opening ledger effect
CREATE TABLE palmy.debts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id uuid NOT NULL REFERENCES palmy.households(id),
  name text NOT NULL,
  direction text NOT NULL CHECK(direction IN ('payable','receivable')),
  origin text NOT NULL CHECK(origin IN ('cash','goods','prior')),
  original_principal palmy.money NOT NULL CHECK(original_principal>0),
  annual_rate numeric(9,6) CHECK(annual_rate>=0),
  term_months integer CHECK(term_months>0),
  opened_on date NOT NULL,
  due_on date,
  phone_ciphertext bytea,
  notes text,
  include_in_net_worth boolean NOT NULL DEFAULT true,
  archived_at timestamptz,
  account_id uuid NOT NULL,
  origin_entry_id uuid,
  member_id uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  version bigint NOT NULL DEFAULT 1 CHECK(version>0),
  UNIQUE(household_id,id)
);

-- Principal/interest/fee breakdown for settlement
CREATE TABLE palmy.debt_payments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id uuid NOT NULL REFERENCES palmy.households(id),
  principal palmy.money NOT NULL CHECK(principal>0),
  interest palmy.money NOT NULL DEFAULT 0 CHECK(interest>=0),
  fee palmy.money NOT NULL DEFAULT 0 CHECK(fee>=0),
  paid_on date NOT NULL,
  debt_id uuid NOT NULL,
  entry_id uuid NOT NULL,
  reverses_payment_id uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  version bigint NOT NULL DEFAULT 1 CHECK(version>0),
  UNIQUE(household_id,id),
  UNIQUE(household_id,entry_id),
  UNIQUE(household_id,reverses_payment_id)
);

-- Savings objective; value derived from reservations and linked holdings
CREATE TABLE palmy.goals (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id uuid NOT NULL REFERENCES palmy.households(id),
  name text NOT NULL,
  type text NOT NULL CHECK(type IN ('holiday','emergency','vehicle','wedding','property','education','retirement','other')),
  target_amount palmy.money NOT NULL CHECK(target_amount>0),
  target_on date,
  notes text,
  include_in_net_worth boolean NOT NULL DEFAULT true,
  archived_at timestamptz,
  default_wallet_id uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  version bigint NOT NULL DEFAULT 1 CHECK(version>0),
  UNIQUE(household_id,id)
);

-- Signed cash reservation changes; not additional money
CREATE TABLE palmy.goal_movements (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id uuid NOT NULL REFERENCES palmy.households(id),
  amount palmy.money NOT NULL CHECK(amount<>0),
  kind text NOT NULL CHECK(kind IN ('reserve','release')),
  effective_on date NOT NULL,
  note text,
  goal_id uuid NOT NULL,
  wallet_id uuid NOT NULL,
  entry_id uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  version bigint NOT NULL DEFAULT 1 CHECK(version>0),
  UNIQUE(household_id,id),
  CHECK((kind='reserve' AND amount>0) OR (kind='release' AND amount<0))
);

-- Investment class and remaining position read model
CREATE TABLE palmy.asset_holdings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id uuid NOT NULL REFERENCES palmy.households(id),
  name text NOT NULL,
  asset_class text NOT NULL CHECK(asset_class IN ('gold','silver','dinar','fx','stock','etf','crypto','bond','deposit','mutual_fund','property','other')),
  symbol text,
  broker text,
  quote_currency char(3) NOT NULL DEFAULT 'IDR',
  unit text NOT NULL,
  annual_rate numeric(9,6),
  matures_on date,
  include_in_net_worth boolean NOT NULL DEFAULT true,
  archived_at timestamptz,
  account_id uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  version bigint NOT NULL DEFAULT 1 CHECK(version>0),
  UNIQUE(household_id,id),
  UNIQUE(household_id,account_id)
);

-- Purchase, sale, income or audited quantity correction
CREATE TABLE palmy.asset_trades (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id uuid NOT NULL REFERENCES palmy.households(id),
  kind text NOT NULL CHECK(kind IN ('buy','sell','dividend','unit_correction','reversal')),
  quantity_delta palmy.quantity NOT NULL,
  unit_price palmy.money CHECK(unit_price>=0),
  gross_amount palmy.money NOT NULL CHECK(gross_amount>=0),
  fee palmy.money NOT NULL DEFAULT 0 CHECK(fee>=0),
  cost_basis_delta palmy.money NOT NULL,
  effective_on date NOT NULL,
  reason text,
  holding_id uuid NOT NULL,
  entry_id uuid,
  reverses_trade_id uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  version bigint NOT NULL DEFAULT 1 CHECK(version>0),
  UNIQUE(household_id,id),
  CHECK((kind='buy' AND quantity_delta>0 AND cost_basis_delta>=0) OR (kind='sell' AND quantity_delta<0 AND cost_basis_delta<=0) OR (kind='dividend' AND quantity_delta=0 AND cost_basis_delta=0) OR (kind='unit_correction' AND cost_basis_delta=0 AND reason IS NOT NULL) OR (kind='reversal' AND reverses_trade_id IS NOT NULL)),
  CHECK((kind='reversal')=(reverses_trade_id IS NOT NULL)),
  UNIQUE(household_id,reverses_trade_id)
);

-- Timestamped valuation provenance, never overwrite history
CREATE TABLE palmy.asset_quotes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id uuid NOT NULL REFERENCES palmy.households(id),
  unit_price palmy.money NOT NULL CHECK(unit_price>=0),
  currency char(3) NOT NULL,
  base_conversion_rate palmy.rate NOT NULL CHECK(base_conversion_rate>0),
  quoted_at timestamptz NOT NULL,
  source text NOT NULL,
  is_manual boolean NOT NULL DEFAULT false,
  holding_id uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  version bigint NOT NULL DEFAULT 1 CHECK(version>0),
  UNIQUE(household_id,id)
);

-- Exclusive whole-holding link to prevent duplicate goal progress
CREATE TABLE palmy.goal_asset_links (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id uuid NOT NULL REFERENCES palmy.households(id),
  goal_id uuid NOT NULL,
  holding_id uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  version bigint NOT NULL DEFAULT 1 CHECK(version>0),
  UNIQUE(household_id,id),
  UNIQUE(household_id,holding_id)
);

-- Income or portfolio allocation plan
CREATE TABLE palmy.allocation_plans (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id uuid NOT NULL REFERENCES palmy.households(id),
  name text NOT NULL,
  kind text NOT NULL CHECK(kind IN ('income','portfolio')),
  income_amount palmy.money CHECK(income_amount>=0),
  state text NOT NULL DEFAULT 'draft' CHECK(state IN ('draft','active','archived')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  version bigint NOT NULL DEFAULT 1 CHECK(version>0),
  UNIQUE(household_id,id)
);

-- Basis-point targets and optional budget/goal mapping
CREATE TABLE palmy.allocation_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id uuid NOT NULL REFERENCES palmy.households(id),
  name text NOT NULL,
  basis_points integer NOT NULL CHECK(basis_points BETWEEN 0 AND 10000),
  asset_class text,
  sort_order integer NOT NULL DEFAULT 0,
  plan_id uuid NOT NULL,
  category_id uuid,
  goal_id uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  version bigint NOT NULL DEFAULT 1 CHECK(version>0),
  UNIQUE(household_id,id),
  CHECK(num_nonnulls(category_id,goal_id,asset_class)<=1)
);

-- Reviewable recurring financial draft
CREATE TABLE palmy.recurring_templates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id uuid NOT NULL REFERENCES palmy.households(id),
  name text NOT NULL,
  frequency text NOT NULL CHECK(frequency IN ('monthly','yearly')),
  day_of_month smallint NOT NULL CHECK(day_of_month BETWEEN 1 AND 31),
  month_of_year smallint CHECK(month_of_year BETWEEN 1 AND 12),
  amount palmy.money NOT NULL CHECK(amount>0),
  fee palmy.money NOT NULL DEFAULT 0 CHECK(fee>=0),
  direction text NOT NULL CHECK(direction IN ('income','expense')),
  paused_at timestamptz,
  wallet_id uuid NOT NULL,
  category_id uuid,
  member_id uuid,
  debt_id uuid,
  goal_id uuid,
  holding_id uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  version bigint NOT NULL DEFAULT 1 CHECK(version>0),
  UNIQUE(household_id,id),
  CHECK((frequency='yearly')=(month_of_year IS NOT NULL)),
  CHECK(num_nonnulls(debt_id,goal_id,holding_id)<=1)
);

-- Exactly one posted occurrence per due date
CREATE TABLE palmy.recurring_occurrences (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id uuid NOT NULL REFERENCES palmy.households(id),
  due_on date NOT NULL,
  template_id uuid NOT NULL,
  entry_id uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  version bigint NOT NULL DEFAULT 1 CHECK(version>0),
  UNIQUE(household_id,id),
  UNIQUE(household_id,template_id,due_on)
);

-- Organized grocery lists
CREATE TABLE palmy.shopping_sections (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id uuid NOT NULL REFERENCES palmy.households(id),
  name text NOT NULL,
  sort_order integer NOT NULL DEFAULT 0,
  archived_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  version bigint NOT NULL DEFAULT 1 CHECK(version>0),
  UNIQUE(household_id,id)
);

-- Current grocery checklist item
CREATE TABLE palmy.shopping_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id uuid NOT NULL REFERENCES palmy.households(id),
  name text NOT NULL,
  quantity palmy.quantity NOT NULL CHECK(quantity>0),
  unit text,
  unit_price palmy.money NOT NULL CHECK(unit_price>=0),
  selected boolean NOT NULL DEFAULT false,
  sort_order integer NOT NULL DEFAULT 0,
  archived_at timestamptz,
  section_id uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  version bigint NOT NULL DEFAULT 1 CHECK(version>0),
  UNIQUE(household_id,id)
);

-- Immutable checkout record with optional financial posting
CREATE TABLE palmy.shopping_purchases (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id uuid NOT NULL REFERENCES palmy.households(id),
  purchased_on date NOT NULL,
  total palmy.money NOT NULL CHECK(total>=0),
  record_only boolean NOT NULL DEFAULT false,
  entry_id uuid,
  merchant_id uuid,
  replaces_purchase_id uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  version bigint NOT NULL DEFAULT 1 CHECK(version>0),
  UNIQUE(household_id,id),
  CHECK(record_only=(entry_id IS NULL)),
  UNIQUE(household_id,replaces_purchase_id)
);

-- Snapshot lines preserve price history
CREATE TABLE palmy.shopping_purchase_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id uuid NOT NULL REFERENCES palmy.households(id),
  name text NOT NULL,
  quantity palmy.quantity NOT NULL CHECK(quantity>0),
  unit_price palmy.money NOT NULL CHECK(unit_price>=0),
  line_total palmy.money NOT NULL CHECK(line_total>=0),
  purchase_id uuid NOT NULL,
  shopping_item_id uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  version bigint NOT NULL DEFAULT 1 CHECK(version>0),
  UNIQUE(household_id,id)
);

-- Recurring household needs
CREATE TABLE palmy.shopping_routines (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id uuid NOT NULL REFERENCES palmy.households(id),
  name text NOT NULL,
  interval_days integer NOT NULL CHECK(interval_days>0),
  quantity palmy.quantity NOT NULL CHECK(quantity>0),
  estimated_price palmy.money CHECK(estimated_price>=0),
  next_due_on date,
  paused_at timestamptz,
  section_id uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  version bigint NOT NULL DEFAULT 1 CHECK(version>0),
  UNIQUE(household_id,id)
);

-- Event or checklist grouping
CREATE TABLE palmy.calendar_categories (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id uuid NOT NULL REFERENCES palmy.households(id),
  name text NOT NULL,
  kind text NOT NULL CHECK(kind IN ('event','checklist')),
  color text,
  sort_order integer NOT NULL DEFAULT 0,
  archived_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  version bigint NOT NULL DEFAULT 1 CHECK(version>0),
  UNIQUE(household_id,id)
);

-- Date-only or timed event/task series
CREATE TABLE palmy.calendar_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id uuid NOT NULL REFERENCES palmy.households(id),
  title text NOT NULL CHECK(length(trim(title))>0),
  kind text NOT NULL CHECK(kind IN ('event','task')),
  starts_on date,
  ends_on date,
  local_time time,
  timezone text NOT NULL,
  assignee_label text,
  rrule text,
  completed_at timestamptz,
  sort_order integer NOT NULL DEFAULT 0,
  archived_at timestamptz,
  category_id uuid NOT NULL,
  assignee_member_id uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  version bigint NOT NULL DEFAULT 1 CHECK(version>0),
  UNIQUE(household_id,id),
  CHECK(ends_on IS NULL OR (starts_on IS NOT NULL AND ends_on>=starts_on)),
  CHECK(kind='task' OR starts_on IS NOT NULL),
  CHECK(local_time IS NULL OR starts_on IS NOT NULL)
);

-- Completion, reschedule or cancellation of one recurring occurrence
CREATE TABLE palmy.calendar_exceptions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id uuid NOT NULL REFERENCES palmy.households(id),
  occurrence_on date NOT NULL,
  override_on date,
  cancelled boolean NOT NULL DEFAULT false,
  completed_at timestamptz,
  item_id uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  version bigint NOT NULL DEFAULT 1 CHECK(version>0),
  UNIQUE(household_id,id),
  UNIQUE(household_id,item_id,occurrence_on)
);

-- Offset and delivery-channel preferences
CREATE TABLE palmy.calendar_reminders (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id uuid NOT NULL REFERENCES palmy.households(id),
  offset_minutes integer NOT NULL CHECK(offset_minutes>=0),
  channel text NOT NULL CHECK(channel IN ('in_app','push')),
  item_id uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  version bigint NOT NULL DEFAULT 1 CHECK(version>0),
  UNIQUE(household_id,id),
  UNIQUE(household_id,item_id,offset_minutes,channel)
);

-- Revocable hashed read-only calendar tokens
CREATE TABLE palmy.calendar_feeds (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id uuid NOT NULL REFERENCES palmy.households(id),
  token_digest text NOT NULL UNIQUE,
  revoked_at timestamptz,
  last_used_at timestamptz,
  created_by uuid NOT NULL REFERENCES palmy.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  version bigint NOT NULL DEFAULT 1 CHECK(version>0),
  UNIQUE(household_id,id)
);

-- Vehicle, home or electronic equipment
CREATE TABLE palmy.maintenance_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id uuid NOT NULL REFERENCES palmy.households(id),
  name text NOT NULL,
  kind text NOT NULL CHECK(kind IN ('vehicle','home','electronic')),
  subtype text,
  interval_days integer CHECK(interval_days>0),
  next_due_on date,
  notes text,
  archived_at timestamptz,
  calendar_item_id uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  version bigint NOT NULL DEFAULT 1 CHECK(version>0),
  UNIQUE(household_id,id)
);

-- Service history and optional expense
CREATE TABLE palmy.service_records (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id uuid NOT NULL REFERENCES palmy.households(id),
  description text NOT NULL,
  serviced_on date NOT NULL,
  cost palmy.money NOT NULL CHECK(cost>=0),
  record_only boolean NOT NULL DEFAULT false,
  next_due_on date,
  notes text,
  maintenance_item_id uuid NOT NULL,
  entry_id uuid,
  replaces_service_id uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  version bigint NOT NULL DEFAULT 1 CHECK(version>0),
  UNIQUE(household_id,id),
  CHECK(record_only=(entry_id IS NULL)),
  UNIQUE(household_id,replaces_service_id)
);

-- PIN-gated useful URLs
CREATE TABLE palmy.important_links (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id uuid NOT NULL REFERENCES palmy.households(id),
  name text NOT NULL CHECK(length(trim(name))>0),
  url text NOT NULL CHECK(url ~ '^https?://[^[:space:]]+$'),
  sort_order integer NOT NULL DEFAULT 0,
  archived_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  version bigint NOT NULL DEFAULT 1 CHECK(version>0),
  UNIQUE(household_id,id)
);

-- Versioned calculation inputs and immutable result snapshot
CREATE TABLE palmy.calculator_scenarios (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id uuid NOT NULL REFERENCES palmy.households(id),
  name text NOT NULL,
  type text NOT NULL CHECK(type IN ('loan','takeover','education')),
  formula_version text NOT NULL,
  inputs jsonb NOT NULL CHECK(jsonb_typeof(inputs)='object'),
  result jsonb NOT NULL CHECK(jsonb_typeof(result)='object'),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  version bigint NOT NULL DEFAULT 1 CHECK(version>0),
  UNIQUE(household_id,id)
);

-- Private object storage metadata and scanning state
CREATE TABLE palmy.files (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id uuid NOT NULL REFERENCES palmy.households(id),
  storage_key text NOT NULL UNIQUE,
  mime_type text NOT NULL,
  byte_size bigint NOT NULL CHECK(byte_size BETWEEN 1 AND 20971520),
  sha256 text NOT NULL CHECK(length(sha256)=64),
  state text NOT NULL CHECK(state IN ('pending','clean','rejected','deleted')),
  uploaded_by uuid NOT NULL REFERENCES palmy.users(id),
  expires_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  version bigint NOT NULL DEFAULT 1 CHECK(version>0),
  UNIQUE(household_id,id)
);

-- Typed attachment link, exactly one resource
CREATE TABLE palmy.file_links (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id uuid NOT NULL REFERENCES palmy.households(id),
  file_id uuid NOT NULL,
  entry_id uuid,
  service_id uuid,
  asset_trade_id uuid,
  calendar_item_id uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  version bigint NOT NULL DEFAULT 1 CHECK(version>0),
  UNIQUE(household_id,id),
  CHECK(num_nonnulls(entry_id,service_id,asset_trade_id,calendar_item_id)=1)
);

-- Async imports, exports, OCR and insight work
CREATE TABLE palmy.jobs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id uuid NOT NULL REFERENCES palmy.households(id),
  kind text NOT NULL CHECK(kind IN ('import','export','ocr','insight','sheets_sync','file_scan','reset','delete_account','quote_refresh')),
  state text NOT NULL DEFAULT 'queued' CHECK(state IN ('queued','running','review','succeeded','failed','cancelled')),
  requested_by uuid NOT NULL REFERENCES palmy.users(id),
  options jsonb NOT NULL DEFAULT '{}',
  result jsonb NOT NULL DEFAULT '{}',
  error_code text,
  attempts integer NOT NULL DEFAULT 0 CHECK(attempts>=0),
  started_at timestamptz,
  completed_at timestamptz,
  input_file_id uuid,
  output_file_id uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  version bigint NOT NULL DEFAULT 1 CHECK(version>0),
  UNIQUE(household_id,id)
);

-- Preview, row errors and duplicate identity
CREATE TABLE palmy.import_rows (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id uuid NOT NULL REFERENCES palmy.households(id),
  row_number integer NOT NULL CHECK(row_number>0),
  source_fingerprint text NOT NULL,
  normalized_data jsonb NOT NULL,
  errors jsonb NOT NULL DEFAULT '[]',
  state text NOT NULL DEFAULT 'pending' CHECK(state IN ('pending','valid','invalid','committed','skipped')),
  job_id uuid NOT NULL,
  entry_id uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  version bigint NOT NULL DEFAULT 1 CHECK(version>0),
  UNIQUE(household_id,id),
  UNIQUE(household_id,job_id,row_number)
);

-- External integration consent and secret reference
CREATE TABLE palmy.integrations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id uuid NOT NULL REFERENCES palmy.households(id),
  provider text NOT NULL CHECK(provider='google_sheets'),
  state text NOT NULL CHECK(state IN ('connected','revoked','expired')),
  scopes text[] NOT NULL,
  credential_secret_ref text,
  external_resource_id text,
  connected_by uuid NOT NULL REFERENCES palmy.users(id),
  revoked_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  version bigint NOT NULL DEFAULT 1 CHECK(version>0),
  UNIQUE(household_id,id),
  UNIQUE(household_id,provider)
);

-- PIN verifier only; secret values never exported
CREATE TABLE palmy.pin_credentials (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id uuid NOT NULL REFERENCES palmy.households(id),
  user_id uuid NOT NULL REFERENCES palmy.users(id),
  argon2id_verifier text NOT NULL,
  failed_attempts integer NOT NULL DEFAULT 0 CHECK(failed_attempts>=0),
  locked_until timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  version bigint NOT NULL DEFAULT 1 CHECK(version>0),
  UNIQUE(household_id,id),
  UNIQUE(household_id,user_id)
);

-- Short-lived scoped authorization after identity/PIN verification
CREATE TABLE palmy.step_up_grants (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id uuid NOT NULL REFERENCES palmy.households(id),
  user_id uuid NOT NULL REFERENCES palmy.users(id),
  token_digest text NOT NULL UNIQUE,
  scope text NOT NULL CHECK(scope IN ('links','reset','delete_account','payout_destination','pin_change','calendar_feed')),
  expires_at timestamptz NOT NULL,
  used_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  version bigint NOT NULL DEFAULT 1 CHECK(version>0),
  UNIQUE(household_id,id)
);

-- Expiring reviewable lifecycle plan
CREATE TABLE palmy.destructive_plans (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id uuid NOT NULL REFERENCES palmy.households(id),
  user_id uuid NOT NULL REFERENCES palmy.users(id),
  scope text NOT NULL CHECK(scope IN ('wallet','household','account')),
  target_id uuid NOT NULL,
  plan_hash text NOT NULL,
  impact jsonb NOT NULL,
  confirmation_phrase text NOT NULL,
  expires_at timestamptz NOT NULL,
  consumed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  version bigint NOT NULL DEFAULT 1 CHECK(version>0),
  UNIQUE(household_id,id)
);

-- Optional push endpoint and encrypted keys
CREATE TABLE palmy.device_subscriptions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id uuid NOT NULL REFERENCES palmy.households(id),
  user_id uuid NOT NULL REFERENCES palmy.users(id),
  endpoint_digest text NOT NULL,
  endpoint_ciphertext bytea NOT NULL,
  keys_ciphertext bytea NOT NULL,
  revoked_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  version bigint NOT NULL DEFAULT 1 CHECK(version>0),
  UNIQUE(household_id,id),
  UNIQUE(household_id,user_id,endpoint_digest)
);

-- Per-user inbox with business-event deduplication
CREATE TABLE palmy.notifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id uuid NOT NULL REFERENCES palmy.households(id),
  user_id uuid NOT NULL REFERENCES palmy.users(id),
  type text NOT NULL,
  title text NOT NULL,
  body text,
  target_path text,
  dedupe_key text NOT NULL,
  read_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  version bigint NOT NULL DEFAULT 1 CHECK(version>0),
  UNIQUE(household_id,id),
  UNIQUE(household_id,user_id,dedupe_key)
);

-- Affiliate identity owned by one user
CREATE TABLE palmy.affiliate_accounts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id uuid NOT NULL REFERENCES palmy.households(id),
  user_id uuid NOT NULL REFERENCES palmy.users(id),
  referral_code text NOT NULL UNIQUE,
  status text NOT NULL CHECK(status IN ('active','suspended')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  version bigint NOT NULL DEFAULT 1 CHECK(version>0),
  UNIQUE(household_id,id),
  UNIQUE(user_id)
);

-- Append-only earned/reversed commissions
CREATE TABLE palmy.affiliate_commissions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id uuid NOT NULL REFERENCES palmy.households(id),
  source_event_id text NOT NULL UNIQUE,
  amount palmy.money NOT NULL CHECK(amount<>0),
  eligible_at timestamptz NOT NULL,
  reason text NOT NULL,
  affiliate_id uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  version bigint NOT NULL DEFAULT 1 CHECK(version>0),
  UNIQUE(household_id,id)
);

-- Encrypted bank details plus safe display suffix
CREATE TABLE palmy.payout_destinations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id uuid NOT NULL REFERENCES palmy.households(id),
  bank_code text NOT NULL,
  account_ciphertext bytea NOT NULL,
  account_last4 char(4) NOT NULL,
  holder_ciphertext bytea NOT NULL,
  verified_at timestamptz,
  archived_at timestamptz,
  affiliate_id uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  version bigint NOT NULL DEFAULT 1 CHECK(version>0),
  UNIQUE(household_id,id)
);

-- Reserved commission withdrawal state machine
CREATE TABLE palmy.payout_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id uuid NOT NULL REFERENCES palmy.households(id),
  amount palmy.money NOT NULL CHECK(amount>=50000),
  state text NOT NULL DEFAULT 'requested' CHECK(state IN ('requested','processing','paid','failed','cancelled')),
  provider_reference text UNIQUE,
  paid_at timestamptz,
  affiliate_id uuid NOT NULL,
  destination_id uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  version bigint NOT NULL DEFAULT 1 CHECK(version>0),
  UNIQUE(household_id,id)
);

-- Affiliate campaign URL and review status
CREATE TABLE palmy.promotion_submissions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id uuid NOT NULL REFERENCES palmy.households(id),
  url text NOT NULL CHECK(url ~ '^https?://[^[:space:]]+$'),
  state text NOT NULL DEFAULT 'pending' CHECK(state IN ('pending','approved','rejected')),
  affiliate_id uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  version bigint NOT NULL DEFAULT 1 CHECK(version>0),
  UNIQUE(household_id,id)
);

-- Public product suggestion without household financial fields
CREATE TABLE palmy.feedback_posts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id uuid NOT NULL REFERENCES palmy.households(id),
  author_id uuid NOT NULL REFERENCES palmy.users(id),
  topic text NOT NULL,
  title text NOT NULL,
  body text NOT NULL,
  status text NOT NULL DEFAULT 'queued' CHECK(status IN ('queued','in_progress','released','declined')),
  is_public boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  version bigint NOT NULL DEFAULT 1 CHECK(version>0),
  UNIQUE(household_id,id)
);

-- One vote per user and post
CREATE TABLE palmy.feedback_votes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES palmy.users(id),
  post_id uuid NOT NULL REFERENCES palmy.feedback_posts(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  version bigint NOT NULL DEFAULT 1 CHECK(version>0),
  UNIQUE(user_id,post_id)
);

-- Versioned global FAQ, help and legal-link metadata
CREATE TABLE palmy.help_articles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  slug text NOT NULL UNIQUE,
  locale text NOT NULL,
  title text NOT NULL,
  body text NOT NULL,
  product_version text NOT NULL,
  published_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  version bigint NOT NULL DEFAULT 1 CHECK(version>0)
);

-- Atomic request-result record scoped to user and route
CREATE TABLE palmy.idempotency_keys (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id uuid NOT NULL REFERENCES palmy.households(id),
  user_id uuid NOT NULL REFERENCES palmy.users(id),
  route text NOT NULL,
  key text NOT NULL,
  request_hash text NOT NULL,
  response_status integer,
  response_body jsonb,
  expires_at timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  version bigint NOT NULL DEFAULT 1 CHECK(version>0),
  UNIQUE(household_id,id),
  UNIQUE(household_id,user_id,route,key)
);

-- Append-only trace without secrets or sensitive descriptions
CREATE TABLE palmy.audit_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id uuid NOT NULL REFERENCES palmy.households(id),
  actor_id uuid REFERENCES palmy.users(id),
  action text NOT NULL,
  resource_type text NOT NULL,
  resource_id uuid,
  request_id uuid NOT NULL,
  metadata jsonb NOT NULL DEFAULT '{}',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  version bigint NOT NULL DEFAULT 1 CHECK(version>0),
  UNIQUE(household_id,id)
);

-- Transactional domain-event delivery
CREATE TABLE palmy.outbox_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id uuid NOT NULL REFERENCES palmy.households(id),
  event_type text NOT NULL,
  aggregate_id uuid NOT NULL,
  dedupe_key text NOT NULL,
  payload jsonb NOT NULL,
  available_at timestamptz NOT NULL DEFAULT now(),
  delivered_at timestamptz,
  attempts integer NOT NULL DEFAULT 0 CHECK(attempts>=0),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  version bigint NOT NULL DEFAULT 1 CHECK(version>0),
  UNIQUE(household_id,id),
  UNIQUE(household_id,dedupe_key)
);

ALTER TABLE palmy.household_settings ADD FOREIGN KEY(household_id,photo_file_id) REFERENCES palmy.files(household_id,id) ON DELETE RESTRICT;
ALTER TABLE palmy.wallets ADD FOREIGN KEY(household_id,account_id) REFERENCES palmy.ledger_accounts(household_id,id) ON DELETE RESTRICT;
ALTER TABLE palmy.wallets ADD FOREIGN KEY(household_id,owner_member_id) REFERENCES palmy.memberships(household_id,id) ON DELETE RESTRICT;
ALTER TABLE palmy.categories ADD FOREIGN KEY(household_id,parent_id) REFERENCES palmy.categories(household_id,id) ON DELETE RESTRICT;
ALTER TABLE palmy.categories ADD FOREIGN KEY(household_id,account_id) REFERENCES palmy.ledger_accounts(household_id,id) ON DELETE RESTRICT;
ALTER TABLE palmy.wallet_category_rules ADD FOREIGN KEY(household_id,wallet_id) REFERENCES palmy.wallets(household_id,id) ON DELETE RESTRICT;
ALTER TABLE palmy.wallet_category_rules ADD FOREIGN KEY(household_id,category_id) REFERENCES palmy.categories(household_id,id) ON DELETE RESTRICT;
ALTER TABLE palmy.budget_limits ADD FOREIGN KEY(household_id,period_id) REFERENCES palmy.budget_periods(household_id,id) ON DELETE RESTRICT;
ALTER TABLE palmy.budget_limits ADD FOREIGN KEY(household_id,category_id) REFERENCES palmy.categories(household_id,id) ON DELETE RESTRICT;
ALTER TABLE palmy.journal_entries ADD FOREIGN KEY(household_id,wallet_id) REFERENCES palmy.wallets(household_id,id) ON DELETE RESTRICT;
ALTER TABLE palmy.journal_entries ADD FOREIGN KEY(household_id,destination_wallet_id) REFERENCES palmy.wallets(household_id,id) ON DELETE RESTRICT;
ALTER TABLE palmy.journal_entries ADD FOREIGN KEY(household_id,merchant_id) REFERENCES palmy.merchants(household_id,id) ON DELETE RESTRICT;
ALTER TABLE palmy.journal_entries ADD FOREIGN KEY(household_id,reverses_entry_id) REFERENCES palmy.journal_entries(household_id,id) ON DELETE RESTRICT;
ALTER TABLE palmy.journal_lines ADD FOREIGN KEY(household_id,entry_id) REFERENCES palmy.journal_entries(household_id,id) ON DELETE RESTRICT;
ALTER TABLE palmy.journal_lines ADD FOREIGN KEY(household_id,account_id) REFERENCES palmy.ledger_accounts(household_id,id) ON DELETE RESTRICT;
ALTER TABLE palmy.entry_allocations ADD FOREIGN KEY(household_id,entry_id) REFERENCES palmy.journal_entries(household_id,id) ON DELETE RESTRICT;
ALTER TABLE palmy.entry_allocations ADD FOREIGN KEY(household_id,category_id) REFERENCES palmy.categories(household_id,id) ON DELETE RESTRICT;
ALTER TABLE palmy.entry_allocations ADD FOREIGN KEY(household_id,member_id) REFERENCES palmy.memberships(household_id,id) ON DELETE RESTRICT;
ALTER TABLE palmy.debts ADD FOREIGN KEY(household_id,account_id) REFERENCES palmy.ledger_accounts(household_id,id) ON DELETE RESTRICT;
ALTER TABLE palmy.debts ADD FOREIGN KEY(household_id,origin_entry_id) REFERENCES palmy.journal_entries(household_id,id) ON DELETE RESTRICT;
ALTER TABLE palmy.debts ADD FOREIGN KEY(household_id,member_id) REFERENCES palmy.memberships(household_id,id) ON DELETE RESTRICT;
ALTER TABLE palmy.debt_payments ADD FOREIGN KEY(household_id,debt_id) REFERENCES palmy.debts(household_id,id) ON DELETE RESTRICT;
ALTER TABLE palmy.debt_payments ADD FOREIGN KEY(household_id,entry_id) REFERENCES palmy.journal_entries(household_id,id) ON DELETE RESTRICT;
ALTER TABLE palmy.debt_payments ADD FOREIGN KEY(household_id,reverses_payment_id) REFERENCES palmy.debt_payments(household_id,id) ON DELETE RESTRICT;
ALTER TABLE palmy.goals ADD FOREIGN KEY(household_id,default_wallet_id) REFERENCES palmy.wallets(household_id,id) ON DELETE RESTRICT;
ALTER TABLE palmy.goal_movements ADD FOREIGN KEY(household_id,goal_id) REFERENCES palmy.goals(household_id,id) ON DELETE RESTRICT;
ALTER TABLE palmy.goal_movements ADD FOREIGN KEY(household_id,wallet_id) REFERENCES palmy.wallets(household_id,id) ON DELETE RESTRICT;
ALTER TABLE palmy.goal_movements ADD FOREIGN KEY(household_id,entry_id) REFERENCES palmy.journal_entries(household_id,id) ON DELETE RESTRICT;
ALTER TABLE palmy.asset_holdings ADD FOREIGN KEY(household_id,account_id) REFERENCES palmy.ledger_accounts(household_id,id) ON DELETE RESTRICT;
ALTER TABLE palmy.asset_trades ADD FOREIGN KEY(household_id,holding_id) REFERENCES palmy.asset_holdings(household_id,id) ON DELETE RESTRICT;
ALTER TABLE palmy.asset_trades ADD FOREIGN KEY(household_id,entry_id) REFERENCES palmy.journal_entries(household_id,id) ON DELETE RESTRICT;
ALTER TABLE palmy.asset_trades ADD FOREIGN KEY(household_id,reverses_trade_id) REFERENCES palmy.asset_trades(household_id,id) ON DELETE RESTRICT;
ALTER TABLE palmy.asset_quotes ADD FOREIGN KEY(household_id,holding_id) REFERENCES palmy.asset_holdings(household_id,id) ON DELETE RESTRICT;
ALTER TABLE palmy.goal_asset_links ADD FOREIGN KEY(household_id,goal_id) REFERENCES palmy.goals(household_id,id) ON DELETE RESTRICT;
ALTER TABLE palmy.goal_asset_links ADD FOREIGN KEY(household_id,holding_id) REFERENCES palmy.asset_holdings(household_id,id) ON DELETE RESTRICT;
ALTER TABLE palmy.allocation_items ADD FOREIGN KEY(household_id,plan_id) REFERENCES palmy.allocation_plans(household_id,id) ON DELETE RESTRICT;
ALTER TABLE palmy.allocation_items ADD FOREIGN KEY(household_id,category_id) REFERENCES palmy.categories(household_id,id) ON DELETE RESTRICT;
ALTER TABLE palmy.allocation_items ADD FOREIGN KEY(household_id,goal_id) REFERENCES palmy.goals(household_id,id) ON DELETE RESTRICT;
ALTER TABLE palmy.recurring_templates ADD FOREIGN KEY(household_id,wallet_id) REFERENCES palmy.wallets(household_id,id) ON DELETE RESTRICT;
ALTER TABLE palmy.recurring_templates ADD FOREIGN KEY(household_id,category_id) REFERENCES palmy.categories(household_id,id) ON DELETE RESTRICT;
ALTER TABLE palmy.recurring_templates ADD FOREIGN KEY(household_id,member_id) REFERENCES palmy.memberships(household_id,id) ON DELETE RESTRICT;
ALTER TABLE palmy.recurring_templates ADD FOREIGN KEY(household_id,debt_id) REFERENCES palmy.debts(household_id,id) ON DELETE RESTRICT;
ALTER TABLE palmy.recurring_templates ADD FOREIGN KEY(household_id,goal_id) REFERENCES palmy.goals(household_id,id) ON DELETE RESTRICT;
ALTER TABLE palmy.recurring_templates ADD FOREIGN KEY(household_id,holding_id) REFERENCES palmy.asset_holdings(household_id,id) ON DELETE RESTRICT;
ALTER TABLE palmy.recurring_occurrences ADD FOREIGN KEY(household_id,template_id) REFERENCES palmy.recurring_templates(household_id,id) ON DELETE RESTRICT;
ALTER TABLE palmy.recurring_occurrences ADD FOREIGN KEY(household_id,entry_id) REFERENCES palmy.journal_entries(household_id,id) ON DELETE RESTRICT;
ALTER TABLE palmy.shopping_items ADD FOREIGN KEY(household_id,section_id) REFERENCES palmy.shopping_sections(household_id,id) ON DELETE RESTRICT;
ALTER TABLE palmy.shopping_purchases ADD FOREIGN KEY(household_id,entry_id) REFERENCES palmy.journal_entries(household_id,id) ON DELETE RESTRICT;
ALTER TABLE palmy.shopping_purchases ADD FOREIGN KEY(household_id,merchant_id) REFERENCES palmy.merchants(household_id,id) ON DELETE RESTRICT;
ALTER TABLE palmy.shopping_purchases ADD FOREIGN KEY(household_id,replaces_purchase_id) REFERENCES palmy.shopping_purchases(household_id,id) ON DELETE RESTRICT;
ALTER TABLE palmy.shopping_purchase_items ADD FOREIGN KEY(household_id,purchase_id) REFERENCES palmy.shopping_purchases(household_id,id) ON DELETE RESTRICT;
ALTER TABLE palmy.shopping_purchase_items ADD FOREIGN KEY(household_id,shopping_item_id) REFERENCES palmy.shopping_items(household_id,id) ON DELETE RESTRICT;
ALTER TABLE palmy.shopping_routines ADD FOREIGN KEY(household_id,section_id) REFERENCES palmy.shopping_sections(household_id,id) ON DELETE RESTRICT;
ALTER TABLE palmy.calendar_items ADD FOREIGN KEY(household_id,category_id) REFERENCES palmy.calendar_categories(household_id,id) ON DELETE RESTRICT;
ALTER TABLE palmy.calendar_items ADD FOREIGN KEY(household_id,assignee_member_id) REFERENCES palmy.memberships(household_id,id) ON DELETE RESTRICT;
ALTER TABLE palmy.calendar_exceptions ADD FOREIGN KEY(household_id,item_id) REFERENCES palmy.calendar_items(household_id,id) ON DELETE RESTRICT;
ALTER TABLE palmy.calendar_reminders ADD FOREIGN KEY(household_id,item_id) REFERENCES palmy.calendar_items(household_id,id) ON DELETE RESTRICT;
ALTER TABLE palmy.maintenance_items ADD FOREIGN KEY(household_id,calendar_item_id) REFERENCES palmy.calendar_items(household_id,id) ON DELETE RESTRICT;
ALTER TABLE palmy.service_records ADD FOREIGN KEY(household_id,maintenance_item_id) REFERENCES palmy.maintenance_items(household_id,id) ON DELETE RESTRICT;
ALTER TABLE palmy.service_records ADD FOREIGN KEY(household_id,entry_id) REFERENCES palmy.journal_entries(household_id,id) ON DELETE RESTRICT;
ALTER TABLE palmy.service_records ADD FOREIGN KEY(household_id,replaces_service_id) REFERENCES palmy.service_records(household_id,id) ON DELETE RESTRICT;
ALTER TABLE palmy.file_links ADD FOREIGN KEY(household_id,file_id) REFERENCES palmy.files(household_id,id) ON DELETE RESTRICT;
ALTER TABLE palmy.file_links ADD FOREIGN KEY(household_id,entry_id) REFERENCES palmy.journal_entries(household_id,id) ON DELETE RESTRICT;
ALTER TABLE palmy.file_links ADD FOREIGN KEY(household_id,service_id) REFERENCES palmy.service_records(household_id,id) ON DELETE RESTRICT;
ALTER TABLE palmy.file_links ADD FOREIGN KEY(household_id,asset_trade_id) REFERENCES palmy.asset_trades(household_id,id) ON DELETE RESTRICT;
ALTER TABLE palmy.file_links ADD FOREIGN KEY(household_id,calendar_item_id) REFERENCES palmy.calendar_items(household_id,id) ON DELETE RESTRICT;
ALTER TABLE palmy.jobs ADD FOREIGN KEY(household_id,input_file_id) REFERENCES palmy.files(household_id,id) ON DELETE RESTRICT;
ALTER TABLE palmy.jobs ADD FOREIGN KEY(household_id,output_file_id) REFERENCES palmy.files(household_id,id) ON DELETE RESTRICT;
ALTER TABLE palmy.import_rows ADD FOREIGN KEY(household_id,job_id) REFERENCES palmy.jobs(household_id,id) ON DELETE RESTRICT;
ALTER TABLE palmy.import_rows ADD FOREIGN KEY(household_id,entry_id) REFERENCES palmy.journal_entries(household_id,id) ON DELETE RESTRICT;
ALTER TABLE palmy.affiliate_commissions ADD FOREIGN KEY(household_id,affiliate_id) REFERENCES palmy.affiliate_accounts(household_id,id) ON DELETE RESTRICT;
ALTER TABLE palmy.payout_destinations ADD FOREIGN KEY(household_id,affiliate_id) REFERENCES palmy.affiliate_accounts(household_id,id) ON DELETE RESTRICT;
ALTER TABLE palmy.payout_requests ADD FOREIGN KEY(household_id,affiliate_id) REFERENCES palmy.affiliate_accounts(household_id,id) ON DELETE RESTRICT;
ALTER TABLE palmy.payout_requests ADD FOREIGN KEY(household_id,destination_id) REFERENCES palmy.payout_destinations(household_id,id) ON DELETE RESTRICT;
ALTER TABLE palmy.promotion_submissions ADD FOREIGN KEY(household_id,affiliate_id) REFERENCES palmy.affiliate_accounts(household_id,id) ON DELETE RESTRICT;

CREATE UNIQUE INDEX one_primary_wallet ON palmy.wallets(household_id) WHERE is_primary AND archived_at IS NULL;
CREATE UNIQUE INDEX unique_live_wallet_name ON palmy.wallets(household_id,lower(name)) WHERE archived_at IS NULL;
CREATE UNIQUE INDEX category_root_name ON palmy.categories(household_id,direction,lower(name)) WHERE parent_id IS NULL AND archived_at IS NULL;
CREATE UNIQUE INDEX category_child_name ON palmy.categories(household_id,parent_id,lower(name)) WHERE parent_id IS NOT NULL AND archived_at IS NULL;
CREATE UNIQUE INDEX imported_once ON palmy.import_rows(household_id,source_fingerprint) WHERE state='committed';
CREATE INDEX journal_period ON palmy.journal_entries(household_id,effective_on DESC,id DESC) WHERE state='posted';
CREATE INDEX quotes_latest ON palmy.asset_quotes(household_id,holding_id,quoted_at DESC,id DESC);
CREATE INDEX calendar_due ON palmy.calendar_items(household_id,starts_on) WHERE archived_at IS NULL;
CREATE INDEX notification_unread ON palmy.notifications(household_id,user_id,created_at DESC) WHERE read_at IS NULL;
CREATE INDEX outbox_pending ON palmy.outbox_events(available_at,id) WHERE delivered_at IS NULL;
CREATE INDEX jobs_pending ON palmy.jobs(state,created_at) WHERE state IN ('queued','running');

CREATE FUNCTION palmy.touch_version() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at=now(); NEW.version=OLD.version+1; RETURN NEW; END $$;
CREATE FUNCTION palmy.reject_mutation() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN RAISE EXCEPTION 'append_only_record' USING ERRCODE='23514'; END $$;
CREATE FUNCTION palmy.protect_entry() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF OLD.state='posted' THEN RAISE EXCEPTION 'posted_entry_immutable' USING ERRCODE='23514'; END IF;
  IF TG_OP='DELETE' THEN RETURN OLD; END IF;
  RETURN NEW;
END $$;
CREATE FUNCTION palmy.protect_line() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE e uuid; h uuid; s text;
BEGIN
  IF TG_OP='INSERT' THEN e=NEW.entry_id; h=NEW.household_id; ELSE e=OLD.entry_id; h=OLD.household_id; END IF;
  SELECT state INTO s FROM palmy.journal_entries WHERE household_id=h AND id=e FOR UPDATE;
  IF s='posted' THEN RAISE EXCEPTION 'posted_lines_immutable' USING ERRCODE='23514'; END IF;
  IF TG_OP='UPDATE' AND (NEW.entry_id,NEW.household_id) IS DISTINCT FROM (OLD.entry_id,OLD.household_id) THEN
    RAISE EXCEPTION 'line_reparent_forbidden' USING ERRCODE='23514';
  END IF;
  IF TG_OP='DELETE' THEN RETURN OLD; END IF; RETURN NEW;
END $$;
CREATE FUNCTION palmy.assert_balanced() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE e uuid; h uuid; s text; n bigint; total numeric;
BEGIN
  IF TG_TABLE_NAME='journal_entries' THEN e=NEW.id;h=NEW.household_id;
  ELSIF TG_OP='DELETE' THEN e=OLD.entry_id;h=OLD.household_id;
  ELSE e=NEW.entry_id;h=NEW.household_id; END IF;
  SELECT state INTO s FROM palmy.journal_entries WHERE household_id=h AND id=e;
  IF s='posted' THEN
    SELECT count(*),sum(amount) INTO n,total FROM palmy.journal_lines WHERE household_id=h AND entry_id=e;
    IF n<2 OR total<>0 THEN RAISE EXCEPTION 'unbalanced_journal %',e USING ERRCODE='23514'; END IF;
  END IF; RETURN NULL;
END $$;
CREATE TRIGGER protect_entry BEFORE UPDATE OR DELETE ON palmy.journal_entries FOR EACH ROW EXECUTE FUNCTION palmy.protect_entry();
CREATE TRIGGER protect_line BEFORE INSERT OR UPDATE OR DELETE ON palmy.journal_lines FOR EACH ROW EXECUTE FUNCTION palmy.protect_line();
CREATE CONSTRAINT TRIGGER balanced_header AFTER INSERT OR UPDATE ON palmy.journal_entries DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION palmy.assert_balanced();
CREATE CONSTRAINT TRIGGER balanced_lines AFTER INSERT OR UPDATE OR DELETE ON palmy.journal_lines DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION palmy.assert_balanced();
CREATE TRIGGER protect_allocation BEFORE INSERT OR UPDATE OR DELETE ON palmy.entry_allocations FOR EACH ROW EXECUTE FUNCTION palmy.protect_line();

CREATE FUNCTION palmy.category_depth() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE p palmy.categories;
BEGIN
 IF NEW.parent_id IS NOT NULL THEN
   SELECT * INTO p FROM palmy.categories WHERE household_id=NEW.household_id AND id=NEW.parent_id FOR UPDATE;
   IF p.parent_id IS NOT NULL OR p.direction<>NEW.direction OR EXISTS(SELECT 1 FROM palmy.categories WHERE household_id=NEW.household_id AND parent_id=NEW.id) THEN
     RAISE EXCEPTION 'category_depth_or_direction' USING ERRCODE='23514';
   END IF;
 END IF; RETURN NEW;
END $$;
CREATE TRIGGER category_depth BEFORE INSERT OR UPDATE ON palmy.categories FOR EACH ROW EXECUTE FUNCTION palmy.category_depth();

CREATE FUNCTION palmy.check_debt_payment() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE original numeric; used numeric; prior palmy.debt_payments;
BEGIN
 SELECT original_principal INTO original FROM palmy.debts WHERE household_id=NEW.household_id AND id=NEW.debt_id FOR UPDATE;
 IF NEW.reverses_payment_id IS NOT NULL THEN
   SELECT * INTO prior FROM palmy.debt_payments WHERE household_id=NEW.household_id AND id=NEW.reverses_payment_id;
   IF prior.id IS NULL OR prior.debt_id<>NEW.debt_id OR prior.reverses_payment_id IS NOT NULL OR
      (prior.principal,prior.interest,prior.fee) IS DISTINCT FROM (NEW.principal,NEW.interest,NEW.fee) THEN
      RAISE EXCEPTION 'invalid_payment_reversal' USING ERRCODE='23514';
   END IF;
 ELSE
   SELECT coalesce(sum(CASE WHEN reverses_payment_id IS NULL THEN principal ELSE -principal END),0) INTO used
   FROM palmy.debt_payments WHERE household_id=NEW.household_id AND debt_id=NEW.debt_id;
   IF used+NEW.principal>original THEN RAISE EXCEPTION 'payment_exceeds_remaining' USING ERRCODE='23514'; END IF;
 END IF; RETURN NEW;
END $$;
CREATE TRIGGER payment_limit BEFORE INSERT ON palmy.debt_payments FOR EACH ROW EXECUTE FUNCTION palmy.check_debt_payment();

CREATE FUNCTION palmy.check_asset_position() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE q numeric; c numeric; prior palmy.asset_trades;
BEGIN
 PERFORM 1 FROM palmy.asset_holdings WHERE household_id=NEW.household_id AND id=NEW.holding_id FOR UPDATE;
 IF NEW.kind='reversal' THEN
   SELECT * INTO prior FROM palmy.asset_trades WHERE household_id=NEW.household_id AND id=NEW.reverses_trade_id;
   IF prior.id IS NULL OR prior.holding_id<>NEW.holding_id OR prior.kind='reversal' OR
      NEW.quantity_delta<>-prior.quantity_delta OR NEW.cost_basis_delta<>-prior.cost_basis_delta OR
      (NEW.gross_amount,NEW.fee) IS DISTINCT FROM (prior.gross_amount,prior.fee) THEN
      RAISE EXCEPTION 'invalid_trade_reversal' USING ERRCODE='23514';
   END IF;
 END IF;
 SELECT coalesce(sum(quantity_delta),0),coalesce(sum(cost_basis_delta),0) INTO q,c
 FROM palmy.asset_trades WHERE household_id=NEW.household_id AND holding_id=NEW.holding_id;
 IF q+NEW.quantity_delta<0 OR c+NEW.cost_basis_delta<0 THEN RAISE EXCEPTION 'negative_asset_position' USING ERRCODE='23514'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER asset_position BEFORE INSERT ON palmy.asset_trades FOR EACH ROW EXECUTE FUNCTION palmy.check_asset_position();

CREATE FUNCTION palmy.check_goal_movement() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE reserved numeric; existing numeric; cash numeric; wallet_kind text;
BEGIN
 SELECT kind INTO wallet_kind FROM palmy.wallets WHERE household_id=NEW.household_id AND id=NEW.wallet_id FOR UPDATE;
 IF wallet_kind='credit' THEN RAISE EXCEPTION 'credit_cannot_fund_reservation' USING ERRCODE='23514'; END IF;
 SELECT coalesce(sum(amount),0) INTO existing FROM palmy.goal_movements WHERE household_id=NEW.household_id AND goal_id=NEW.goal_id AND wallet_id=NEW.wallet_id;
 IF existing+NEW.amount<0 THEN RAISE EXCEPTION 'release_exceeds_reservation' USING ERRCODE='23514'; END IF;
 IF NEW.amount>0 THEN
   SELECT coalesce(sum(amount),0) INTO reserved FROM palmy.goal_movements WHERE household_id=NEW.household_id AND wallet_id=NEW.wallet_id;
   SELECT coalesce(sum(l.amount),0) INTO cash FROM palmy.wallets w
   JOIN palmy.journal_lines l ON l.household_id=w.household_id AND l.account_id=w.account_id
   JOIN palmy.journal_entries e ON e.household_id=l.household_id AND e.id=l.entry_id AND e.state='posted'
   WHERE w.household_id=NEW.household_id AND w.id=NEW.wallet_id;
   IF reserved+NEW.amount>cash THEN RAISE EXCEPTION 'insufficient_free_cash' USING ERRCODE='23514'; END IF;
 END IF; RETURN NEW;
END $$;
CREATE TRIGGER goal_movement_limit BEFORE INSERT ON palmy.goal_movements FOR EACH ROW EXECUTE FUNCTION palmy.check_goal_movement();

CREATE FUNCTION palmy.check_active_allocation() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE p uuid; h uuid; s text; total bigint;
BEGIN
 IF TG_TABLE_NAME='allocation_items' AND TG_OP='UPDATE' THEN
   IF NEW.plan_id IS DISTINCT FROM OLD.plan_id THEN RAISE EXCEPTION 'allocation_reparent_forbidden' USING ERRCODE='23514'; END IF;
 END IF;
 IF TG_TABLE_NAME='allocation_plans' THEN p=NEW.id;h=NEW.household_id;
 ELSIF TG_OP='DELETE' THEN p=OLD.plan_id;h=OLD.household_id;
 ELSE p=NEW.plan_id;h=NEW.household_id; END IF;
 SELECT state INTO s FROM palmy.allocation_plans WHERE id=p AND household_id=h FOR UPDATE;
 IF s='active' THEN
   SELECT sum(basis_points) INTO total FROM palmy.allocation_items WHERE plan_id=p AND household_id=h;
   IF total IS DISTINCT FROM 10000 THEN RAISE EXCEPTION 'allocation_must_total_100_percent' USING ERRCODE='23514'; END IF;
 END IF; RETURN NULL;
END $$;
CREATE CONSTRAINT TRIGGER active_allocation AFTER INSERT OR UPDATE ON palmy.allocation_plans DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION palmy.check_active_allocation();
CREATE CONSTRAINT TRIGGER active_allocation_items AFTER INSERT OR UPDATE OR DELETE ON palmy.allocation_items DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION palmy.check_active_allocation();

-- Security context is set by trusted API after identity validation, transaction-locally.
CREATE FUNCTION palmy.user_id() RETURNS uuid LANGUAGE sql STABLE AS $$ SELECT nullif(current_setting('app.user_id',true),'')::uuid $$;
CREATE FUNCTION palmy.household_id() RETURNS uuid LANGUAGE sql STABLE AS $$ SELECT nullif(current_setting('app.household_id',true),'')::uuid $$;
-- Owner bypass on membership lookup is deliberate to avoid recursive RLS; no dynamic SQL.
-- The SECURITY DEFINER owner must be the migration role, never the runtime role.
CREATE FUNCTION palmy.can_access(h uuid) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,palmy AS $$
 SELECT h=palmy.household_id() AND EXISTS(SELECT 1 FROM palmy.memberships m WHERE m.household_id=h AND m.user_id=palmy.user_id() AND m.status='active')
$$;
CREATE FUNCTION palmy.is_owner(h uuid) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,palmy AS $$
 SELECT palmy.can_access(h) AND EXISTS(SELECT 1 FROM palmy.memberships m WHERE m.household_id=h AND m.user_id=palmy.user_id() AND m.role='owner' AND m.status='active')
$$;
REVOKE ALL ON FUNCTION palmy.can_access(uuid),palmy.is_owner(uuid) FROM PUBLIC;

CREATE TRIGGER touch BEFORE UPDATE ON palmy.users FOR EACH ROW EXECUTE FUNCTION palmy.touch_version();
CREATE TRIGGER touch BEFORE UPDATE ON palmy.households FOR EACH ROW EXECUTE FUNCTION palmy.touch_version();
CREATE TRIGGER touch BEFORE UPDATE ON palmy.memberships FOR EACH ROW EXECUTE FUNCTION palmy.touch_version();
ALTER TABLE palmy.memberships ENABLE ROW LEVEL SECURITY;
CREATE POLICY tenant_read ON palmy.memberships FOR SELECT USING (palmy.can_access(household_id));
CREATE POLICY owner_insert ON palmy.memberships FOR INSERT WITH CHECK (palmy.is_owner(household_id));
CREATE POLICY owner_update ON palmy.memberships FOR UPDATE USING (palmy.is_owner(household_id)) WITH CHECK (palmy.is_owner(household_id));
CREATE POLICY owner_delete ON palmy.memberships FOR DELETE USING (palmy.is_owner(household_id));
CREATE TRIGGER touch BEFORE UPDATE ON palmy.invitations FOR EACH ROW EXECUTE FUNCTION palmy.touch_version();
ALTER TABLE palmy.invitations ENABLE ROW LEVEL SECURITY;
ALTER TABLE palmy.invitations FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_read ON palmy.invitations FOR SELECT USING (palmy.can_access(household_id));
CREATE POLICY owner_insert ON palmy.invitations FOR INSERT WITH CHECK (palmy.is_owner(household_id));
CREATE POLICY owner_update ON palmy.invitations FOR UPDATE USING (palmy.is_owner(household_id)) WITH CHECK (palmy.is_owner(household_id));
CREATE POLICY owner_delete ON palmy.invitations FOR DELETE USING (palmy.is_owner(household_id));
CREATE TRIGGER touch BEFORE UPDATE ON palmy.household_settings FOR EACH ROW EXECUTE FUNCTION palmy.touch_version();
ALTER TABLE palmy.household_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE palmy.household_settings FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_read ON palmy.household_settings FOR SELECT USING (palmy.can_access(household_id));
CREATE POLICY owner_insert ON palmy.household_settings FOR INSERT WITH CHECK (palmy.is_owner(household_id));
CREATE POLICY owner_update ON palmy.household_settings FOR UPDATE USING (palmy.is_owner(household_id)) WITH CHECK (palmy.is_owner(household_id));
CREATE POLICY owner_delete ON palmy.household_settings FOR DELETE USING (palmy.is_owner(household_id));
CREATE INDEX ON palmy.household_settings(household_id,photo_file_id);
CREATE TRIGGER touch BEFORE UPDATE ON palmy.ledger_accounts FOR EACH ROW EXECUTE FUNCTION palmy.touch_version();
ALTER TABLE palmy.ledger_accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE palmy.ledger_accounts FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_scope ON palmy.ledger_accounts USING (palmy.can_access(household_id)) WITH CHECK (palmy.can_access(household_id));
CREATE TRIGGER touch BEFORE UPDATE ON palmy.wallets FOR EACH ROW EXECUTE FUNCTION palmy.touch_version();
ALTER TABLE palmy.wallets ENABLE ROW LEVEL SECURITY;
ALTER TABLE palmy.wallets FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_scope ON palmy.wallets USING (palmy.can_access(household_id)) WITH CHECK (palmy.can_access(household_id));
CREATE INDEX ON palmy.wallets(household_id,account_id);
CREATE INDEX ON palmy.wallets(household_id,owner_member_id);
CREATE TRIGGER touch BEFORE UPDATE ON palmy.categories FOR EACH ROW EXECUTE FUNCTION palmy.touch_version();
ALTER TABLE palmy.categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE palmy.categories FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_scope ON palmy.categories USING (palmy.can_access(household_id)) WITH CHECK (palmy.can_access(household_id));
CREATE INDEX ON palmy.categories(household_id,parent_id);
CREATE INDEX ON palmy.categories(household_id,account_id);
CREATE TRIGGER touch BEFORE UPDATE ON palmy.wallet_category_rules FOR EACH ROW EXECUTE FUNCTION palmy.touch_version();
ALTER TABLE palmy.wallet_category_rules ENABLE ROW LEVEL SECURITY;
ALTER TABLE palmy.wallet_category_rules FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_scope ON palmy.wallet_category_rules USING (palmy.can_access(household_id)) WITH CHECK (palmy.can_access(household_id));
CREATE INDEX ON palmy.wallet_category_rules(household_id,wallet_id);
CREATE INDEX ON palmy.wallet_category_rules(household_id,category_id);
CREATE TRIGGER touch BEFORE UPDATE ON palmy.budget_periods FOR EACH ROW EXECUTE FUNCTION palmy.touch_version();
ALTER TABLE palmy.budget_periods ENABLE ROW LEVEL SECURITY;
ALTER TABLE palmy.budget_periods FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_scope ON palmy.budget_periods USING (palmy.can_access(household_id)) WITH CHECK (palmy.can_access(household_id));
CREATE TRIGGER touch BEFORE UPDATE ON palmy.budget_limits FOR EACH ROW EXECUTE FUNCTION palmy.touch_version();
ALTER TABLE palmy.budget_limits ENABLE ROW LEVEL SECURITY;
ALTER TABLE palmy.budget_limits FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_scope ON palmy.budget_limits USING (palmy.can_access(household_id)) WITH CHECK (palmy.can_access(household_id));
CREATE INDEX ON palmy.budget_limits(household_id,period_id);
CREATE INDEX ON palmy.budget_limits(household_id,category_id);
CREATE TRIGGER touch BEFORE UPDATE ON palmy.merchants FOR EACH ROW EXECUTE FUNCTION palmy.touch_version();
ALTER TABLE palmy.merchants ENABLE ROW LEVEL SECURITY;
ALTER TABLE palmy.merchants FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_scope ON palmy.merchants USING (palmy.can_access(household_id)) WITH CHECK (palmy.can_access(household_id));
CREATE TRIGGER touch BEFORE UPDATE ON palmy.journal_entries FOR EACH ROW EXECUTE FUNCTION palmy.touch_version();
ALTER TABLE palmy.journal_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE palmy.journal_entries FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_scope ON palmy.journal_entries USING (palmy.can_access(household_id)) WITH CHECK (palmy.can_access(household_id));
CREATE INDEX ON palmy.journal_entries(household_id,wallet_id);
CREATE INDEX ON palmy.journal_entries(household_id,destination_wallet_id);
CREATE INDEX ON palmy.journal_entries(household_id,merchant_id);
CREATE INDEX ON palmy.journal_entries(household_id,reverses_entry_id);
CREATE TRIGGER touch BEFORE UPDATE ON palmy.journal_lines FOR EACH ROW EXECUTE FUNCTION palmy.touch_version();
ALTER TABLE palmy.journal_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE palmy.journal_lines FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_scope ON palmy.journal_lines USING (palmy.can_access(household_id)) WITH CHECK (palmy.can_access(household_id));
CREATE INDEX ON palmy.journal_lines(household_id,entry_id);
CREATE INDEX ON palmy.journal_lines(household_id,account_id);
CREATE TRIGGER touch BEFORE UPDATE ON palmy.entry_allocations FOR EACH ROW EXECUTE FUNCTION palmy.touch_version();
ALTER TABLE palmy.entry_allocations ENABLE ROW LEVEL SECURITY;
ALTER TABLE palmy.entry_allocations FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_scope ON palmy.entry_allocations USING (palmy.can_access(household_id)) WITH CHECK (palmy.can_access(household_id));
CREATE INDEX ON palmy.entry_allocations(household_id,entry_id);
CREATE INDEX ON palmy.entry_allocations(household_id,category_id);
CREATE INDEX ON palmy.entry_allocations(household_id,member_id);
CREATE TRIGGER touch BEFORE UPDATE ON palmy.debts FOR EACH ROW EXECUTE FUNCTION palmy.touch_version();
ALTER TABLE palmy.debts ENABLE ROW LEVEL SECURITY;
ALTER TABLE palmy.debts FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_scope ON palmy.debts USING (palmy.can_access(household_id)) WITH CHECK (palmy.can_access(household_id));
CREATE INDEX ON palmy.debts(household_id,account_id);
CREATE INDEX ON palmy.debts(household_id,origin_entry_id);
CREATE INDEX ON palmy.debts(household_id,member_id);
CREATE TRIGGER immutable BEFORE UPDATE OR DELETE ON palmy.debt_payments FOR EACH ROW EXECUTE FUNCTION palmy.reject_mutation();
ALTER TABLE palmy.debt_payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE palmy.debt_payments FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_scope ON palmy.debt_payments USING (palmy.can_access(household_id)) WITH CHECK (palmy.can_access(household_id));
CREATE INDEX ON palmy.debt_payments(household_id,debt_id);
CREATE INDEX ON palmy.debt_payments(household_id,entry_id);
CREATE INDEX ON palmy.debt_payments(household_id,reverses_payment_id);
CREATE TRIGGER touch BEFORE UPDATE ON palmy.goals FOR EACH ROW EXECUTE FUNCTION palmy.touch_version();
ALTER TABLE palmy.goals ENABLE ROW LEVEL SECURITY;
ALTER TABLE palmy.goals FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_scope ON palmy.goals USING (palmy.can_access(household_id)) WITH CHECK (palmy.can_access(household_id));
CREATE INDEX ON palmy.goals(household_id,default_wallet_id);
CREATE TRIGGER immutable BEFORE UPDATE OR DELETE ON palmy.goal_movements FOR EACH ROW EXECUTE FUNCTION palmy.reject_mutation();
ALTER TABLE palmy.goal_movements ENABLE ROW LEVEL SECURITY;
ALTER TABLE palmy.goal_movements FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_scope ON palmy.goal_movements USING (palmy.can_access(household_id)) WITH CHECK (palmy.can_access(household_id));
CREATE INDEX ON palmy.goal_movements(household_id,goal_id);
CREATE INDEX ON palmy.goal_movements(household_id,wallet_id);
CREATE INDEX ON palmy.goal_movements(household_id,entry_id);
CREATE TRIGGER touch BEFORE UPDATE ON palmy.asset_holdings FOR EACH ROW EXECUTE FUNCTION palmy.touch_version();
ALTER TABLE palmy.asset_holdings ENABLE ROW LEVEL SECURITY;
ALTER TABLE palmy.asset_holdings FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_scope ON palmy.asset_holdings USING (palmy.can_access(household_id)) WITH CHECK (palmy.can_access(household_id));
CREATE INDEX ON palmy.asset_holdings(household_id,account_id);
CREATE TRIGGER immutable BEFORE UPDATE OR DELETE ON palmy.asset_trades FOR EACH ROW EXECUTE FUNCTION palmy.reject_mutation();
ALTER TABLE palmy.asset_trades ENABLE ROW LEVEL SECURITY;
ALTER TABLE palmy.asset_trades FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_scope ON palmy.asset_trades USING (palmy.can_access(household_id)) WITH CHECK (palmy.can_access(household_id));
CREATE INDEX ON palmy.asset_trades(household_id,holding_id);
CREATE INDEX ON palmy.asset_trades(household_id,entry_id);
CREATE INDEX ON palmy.asset_trades(household_id,reverses_trade_id);
CREATE TRIGGER immutable BEFORE UPDATE OR DELETE ON palmy.asset_quotes FOR EACH ROW EXECUTE FUNCTION palmy.reject_mutation();
ALTER TABLE palmy.asset_quotes ENABLE ROW LEVEL SECURITY;
ALTER TABLE palmy.asset_quotes FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_scope ON palmy.asset_quotes USING (palmy.can_access(household_id)) WITH CHECK (palmy.can_access(household_id));
CREATE INDEX ON palmy.asset_quotes(household_id,holding_id);
CREATE TRIGGER touch BEFORE UPDATE ON palmy.goal_asset_links FOR EACH ROW EXECUTE FUNCTION palmy.touch_version();
ALTER TABLE palmy.goal_asset_links ENABLE ROW LEVEL SECURITY;
ALTER TABLE palmy.goal_asset_links FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_scope ON palmy.goal_asset_links USING (palmy.can_access(household_id)) WITH CHECK (palmy.can_access(household_id));
CREATE INDEX ON palmy.goal_asset_links(household_id,goal_id);
CREATE INDEX ON palmy.goal_asset_links(household_id,holding_id);
CREATE TRIGGER touch BEFORE UPDATE ON palmy.allocation_plans FOR EACH ROW EXECUTE FUNCTION palmy.touch_version();
ALTER TABLE palmy.allocation_plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE palmy.allocation_plans FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_scope ON palmy.allocation_plans USING (palmy.can_access(household_id)) WITH CHECK (palmy.can_access(household_id));
CREATE TRIGGER touch BEFORE UPDATE ON palmy.allocation_items FOR EACH ROW EXECUTE FUNCTION palmy.touch_version();
ALTER TABLE palmy.allocation_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE palmy.allocation_items FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_scope ON palmy.allocation_items USING (palmy.can_access(household_id)) WITH CHECK (palmy.can_access(household_id));
CREATE INDEX ON palmy.allocation_items(household_id,plan_id);
CREATE INDEX ON palmy.allocation_items(household_id,category_id);
CREATE INDEX ON palmy.allocation_items(household_id,goal_id);
CREATE TRIGGER touch BEFORE UPDATE ON palmy.recurring_templates FOR EACH ROW EXECUTE FUNCTION palmy.touch_version();
ALTER TABLE palmy.recurring_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE palmy.recurring_templates FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_scope ON palmy.recurring_templates USING (palmy.can_access(household_id)) WITH CHECK (palmy.can_access(household_id));
CREATE INDEX ON palmy.recurring_templates(household_id,wallet_id);
CREATE INDEX ON palmy.recurring_templates(household_id,category_id);
CREATE INDEX ON palmy.recurring_templates(household_id,member_id);
CREATE INDEX ON palmy.recurring_templates(household_id,debt_id);
CREATE INDEX ON palmy.recurring_templates(household_id,goal_id);
CREATE INDEX ON palmy.recurring_templates(household_id,holding_id);
CREATE TRIGGER immutable BEFORE UPDATE OR DELETE ON palmy.recurring_occurrences FOR EACH ROW EXECUTE FUNCTION palmy.reject_mutation();
ALTER TABLE palmy.recurring_occurrences ENABLE ROW LEVEL SECURITY;
ALTER TABLE palmy.recurring_occurrences FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_scope ON palmy.recurring_occurrences USING (palmy.can_access(household_id)) WITH CHECK (palmy.can_access(household_id));
CREATE INDEX ON palmy.recurring_occurrences(household_id,template_id);
CREATE INDEX ON palmy.recurring_occurrences(household_id,entry_id);
CREATE TRIGGER touch BEFORE UPDATE ON palmy.shopping_sections FOR EACH ROW EXECUTE FUNCTION palmy.touch_version();
ALTER TABLE palmy.shopping_sections ENABLE ROW LEVEL SECURITY;
ALTER TABLE palmy.shopping_sections FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_scope ON palmy.shopping_sections USING (palmy.can_access(household_id)) WITH CHECK (palmy.can_access(household_id));
CREATE TRIGGER touch BEFORE UPDATE ON palmy.shopping_items FOR EACH ROW EXECUTE FUNCTION palmy.touch_version();
ALTER TABLE palmy.shopping_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE palmy.shopping_items FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_scope ON palmy.shopping_items USING (palmy.can_access(household_id)) WITH CHECK (palmy.can_access(household_id));
CREATE INDEX ON palmy.shopping_items(household_id,section_id);
CREATE TRIGGER immutable BEFORE UPDATE OR DELETE ON palmy.shopping_purchases FOR EACH ROW EXECUTE FUNCTION palmy.reject_mutation();
ALTER TABLE palmy.shopping_purchases ENABLE ROW LEVEL SECURITY;
ALTER TABLE palmy.shopping_purchases FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_scope ON palmy.shopping_purchases USING (palmy.can_access(household_id)) WITH CHECK (palmy.can_access(household_id));
CREATE INDEX ON palmy.shopping_purchases(household_id,entry_id);
CREATE INDEX ON palmy.shopping_purchases(household_id,merchant_id);
CREATE INDEX ON palmy.shopping_purchases(household_id,replaces_purchase_id);
CREATE TRIGGER immutable BEFORE UPDATE OR DELETE ON palmy.shopping_purchase_items FOR EACH ROW EXECUTE FUNCTION palmy.reject_mutation();
ALTER TABLE palmy.shopping_purchase_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE palmy.shopping_purchase_items FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_scope ON palmy.shopping_purchase_items USING (palmy.can_access(household_id)) WITH CHECK (palmy.can_access(household_id));
CREATE INDEX ON palmy.shopping_purchase_items(household_id,purchase_id);
CREATE INDEX ON palmy.shopping_purchase_items(household_id,shopping_item_id);
CREATE TRIGGER touch BEFORE UPDATE ON palmy.shopping_routines FOR EACH ROW EXECUTE FUNCTION palmy.touch_version();
ALTER TABLE palmy.shopping_routines ENABLE ROW LEVEL SECURITY;
ALTER TABLE palmy.shopping_routines FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_scope ON palmy.shopping_routines USING (palmy.can_access(household_id)) WITH CHECK (palmy.can_access(household_id));
CREATE INDEX ON palmy.shopping_routines(household_id,section_id);
CREATE TRIGGER touch BEFORE UPDATE ON palmy.calendar_categories FOR EACH ROW EXECUTE FUNCTION palmy.touch_version();
ALTER TABLE palmy.calendar_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE palmy.calendar_categories FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_scope ON palmy.calendar_categories USING (palmy.can_access(household_id)) WITH CHECK (palmy.can_access(household_id));
CREATE TRIGGER touch BEFORE UPDATE ON palmy.calendar_items FOR EACH ROW EXECUTE FUNCTION palmy.touch_version();
ALTER TABLE palmy.calendar_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE palmy.calendar_items FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_scope ON palmy.calendar_items USING (palmy.can_access(household_id)) WITH CHECK (palmy.can_access(household_id));
CREATE INDEX ON palmy.calendar_items(household_id,category_id);
CREATE INDEX ON palmy.calendar_items(household_id,assignee_member_id);
CREATE TRIGGER touch BEFORE UPDATE ON palmy.calendar_exceptions FOR EACH ROW EXECUTE FUNCTION palmy.touch_version();
ALTER TABLE palmy.calendar_exceptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE palmy.calendar_exceptions FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_scope ON palmy.calendar_exceptions USING (palmy.can_access(household_id)) WITH CHECK (palmy.can_access(household_id));
CREATE INDEX ON palmy.calendar_exceptions(household_id,item_id);
CREATE TRIGGER touch BEFORE UPDATE ON palmy.calendar_reminders FOR EACH ROW EXECUTE FUNCTION palmy.touch_version();
ALTER TABLE palmy.calendar_reminders ENABLE ROW LEVEL SECURITY;
ALTER TABLE palmy.calendar_reminders FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_scope ON palmy.calendar_reminders USING (palmy.can_access(household_id)) WITH CHECK (palmy.can_access(household_id));
CREATE INDEX ON palmy.calendar_reminders(household_id,item_id);
CREATE TRIGGER touch BEFORE UPDATE ON palmy.calendar_feeds FOR EACH ROW EXECUTE FUNCTION palmy.touch_version();
ALTER TABLE palmy.calendar_feeds ENABLE ROW LEVEL SECURITY;
ALTER TABLE palmy.calendar_feeds FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_scope ON palmy.calendar_feeds USING (palmy.can_access(household_id)) WITH CHECK (palmy.can_access(household_id));
CREATE TRIGGER touch BEFORE UPDATE ON palmy.maintenance_items FOR EACH ROW EXECUTE FUNCTION palmy.touch_version();
ALTER TABLE palmy.maintenance_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE palmy.maintenance_items FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_scope ON palmy.maintenance_items USING (palmy.can_access(household_id)) WITH CHECK (palmy.can_access(household_id));
CREATE INDEX ON palmy.maintenance_items(household_id,calendar_item_id);
CREATE TRIGGER immutable BEFORE UPDATE OR DELETE ON palmy.service_records FOR EACH ROW EXECUTE FUNCTION palmy.reject_mutation();
ALTER TABLE palmy.service_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE palmy.service_records FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_scope ON palmy.service_records USING (palmy.can_access(household_id)) WITH CHECK (palmy.can_access(household_id));
CREATE INDEX ON palmy.service_records(household_id,maintenance_item_id);
CREATE INDEX ON palmy.service_records(household_id,entry_id);
CREATE INDEX ON palmy.service_records(household_id,replaces_service_id);
CREATE TRIGGER touch BEFORE UPDATE ON palmy.important_links FOR EACH ROW EXECUTE FUNCTION palmy.touch_version();
ALTER TABLE palmy.important_links ENABLE ROW LEVEL SECURITY;
ALTER TABLE palmy.important_links FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_scope ON palmy.important_links USING (palmy.can_access(household_id)) WITH CHECK (palmy.can_access(household_id));
CREATE TRIGGER touch BEFORE UPDATE ON palmy.calculator_scenarios FOR EACH ROW EXECUTE FUNCTION palmy.touch_version();
ALTER TABLE palmy.calculator_scenarios ENABLE ROW LEVEL SECURITY;
ALTER TABLE palmy.calculator_scenarios FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_scope ON palmy.calculator_scenarios USING (palmy.can_access(household_id)) WITH CHECK (palmy.can_access(household_id));
CREATE TRIGGER touch BEFORE UPDATE ON palmy.files FOR EACH ROW EXECUTE FUNCTION palmy.touch_version();
ALTER TABLE palmy.files ENABLE ROW LEVEL SECURITY;
ALTER TABLE palmy.files FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_scope ON palmy.files USING (palmy.can_access(household_id)) WITH CHECK (palmy.can_access(household_id));
CREATE TRIGGER touch BEFORE UPDATE ON palmy.file_links FOR EACH ROW EXECUTE FUNCTION palmy.touch_version();
ALTER TABLE palmy.file_links ENABLE ROW LEVEL SECURITY;
ALTER TABLE palmy.file_links FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_scope ON palmy.file_links USING (palmy.can_access(household_id)) WITH CHECK (palmy.can_access(household_id));
CREATE INDEX ON palmy.file_links(household_id,file_id);
CREATE INDEX ON palmy.file_links(household_id,entry_id);
CREATE INDEX ON palmy.file_links(household_id,service_id);
CREATE INDEX ON palmy.file_links(household_id,asset_trade_id);
CREATE INDEX ON palmy.file_links(household_id,calendar_item_id);
CREATE TRIGGER touch BEFORE UPDATE ON palmy.jobs FOR EACH ROW EXECUTE FUNCTION palmy.touch_version();
ALTER TABLE palmy.jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE palmy.jobs FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_scope ON palmy.jobs USING (palmy.can_access(household_id)) WITH CHECK (palmy.can_access(household_id));
CREATE INDEX ON palmy.jobs(household_id,input_file_id);
CREATE INDEX ON palmy.jobs(household_id,output_file_id);
CREATE TRIGGER touch BEFORE UPDATE ON palmy.import_rows FOR EACH ROW EXECUTE FUNCTION palmy.touch_version();
ALTER TABLE palmy.import_rows ENABLE ROW LEVEL SECURITY;
ALTER TABLE palmy.import_rows FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_scope ON palmy.import_rows USING (palmy.can_access(household_id)) WITH CHECK (palmy.can_access(household_id));
CREATE INDEX ON palmy.import_rows(household_id,job_id);
CREATE INDEX ON palmy.import_rows(household_id,entry_id);
CREATE TRIGGER touch BEFORE UPDATE ON palmy.integrations FOR EACH ROW EXECUTE FUNCTION palmy.touch_version();
ALTER TABLE palmy.integrations ENABLE ROW LEVEL SECURITY;
ALTER TABLE palmy.integrations FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_read ON palmy.integrations FOR SELECT USING (palmy.can_access(household_id));
CREATE POLICY owner_insert ON palmy.integrations FOR INSERT WITH CHECK (palmy.is_owner(household_id));
CREATE POLICY owner_update ON palmy.integrations FOR UPDATE USING (palmy.is_owner(household_id)) WITH CHECK (palmy.is_owner(household_id));
CREATE POLICY owner_delete ON palmy.integrations FOR DELETE USING (palmy.is_owner(household_id));
CREATE TRIGGER touch BEFORE UPDATE ON palmy.pin_credentials FOR EACH ROW EXECUTE FUNCTION palmy.touch_version();
ALTER TABLE palmy.pin_credentials ENABLE ROW LEVEL SECURITY;
ALTER TABLE palmy.pin_credentials FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_scope ON palmy.pin_credentials USING (palmy.can_access(household_id) AND user_id=palmy.user_id()) WITH CHECK (palmy.can_access(household_id) AND user_id=palmy.user_id());
CREATE TRIGGER touch BEFORE UPDATE ON palmy.step_up_grants FOR EACH ROW EXECUTE FUNCTION palmy.touch_version();
ALTER TABLE palmy.step_up_grants ENABLE ROW LEVEL SECURITY;
ALTER TABLE palmy.step_up_grants FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_scope ON palmy.step_up_grants USING (palmy.can_access(household_id) AND user_id=palmy.user_id()) WITH CHECK (palmy.can_access(household_id) AND user_id=palmy.user_id());
CREATE TRIGGER touch BEFORE UPDATE ON palmy.destructive_plans FOR EACH ROW EXECUTE FUNCTION palmy.touch_version();
ALTER TABLE palmy.destructive_plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE palmy.destructive_plans FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_scope ON palmy.destructive_plans USING (palmy.can_access(household_id) AND user_id=palmy.user_id()) WITH CHECK (palmy.can_access(household_id) AND user_id=palmy.user_id());
CREATE TRIGGER touch BEFORE UPDATE ON palmy.device_subscriptions FOR EACH ROW EXECUTE FUNCTION palmy.touch_version();
ALTER TABLE palmy.device_subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE palmy.device_subscriptions FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_scope ON palmy.device_subscriptions USING (palmy.can_access(household_id) AND user_id=palmy.user_id()) WITH CHECK (palmy.can_access(household_id) AND user_id=palmy.user_id());
CREATE TRIGGER touch BEFORE UPDATE ON palmy.notifications FOR EACH ROW EXECUTE FUNCTION palmy.touch_version();
ALTER TABLE palmy.notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE palmy.notifications FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_scope ON palmy.notifications USING (palmy.can_access(household_id) AND user_id=palmy.user_id()) WITH CHECK (palmy.can_access(household_id) AND user_id=palmy.user_id());
CREATE TRIGGER touch BEFORE UPDATE ON palmy.affiliate_accounts FOR EACH ROW EXECUTE FUNCTION palmy.touch_version();
ALTER TABLE palmy.affiliate_accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE palmy.affiliate_accounts FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_scope ON palmy.affiliate_accounts USING (palmy.can_access(household_id) AND user_id=palmy.user_id()) WITH CHECK (palmy.can_access(household_id) AND user_id=palmy.user_id());
CREATE TRIGGER immutable BEFORE UPDATE OR DELETE ON palmy.affiliate_commissions FOR EACH ROW EXECUTE FUNCTION palmy.reject_mutation();
ALTER TABLE palmy.affiliate_commissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE palmy.affiliate_commissions FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_scope ON palmy.affiliate_commissions USING (palmy.can_access(household_id) AND EXISTS(SELECT 1 FROM palmy.affiliate_accounts a WHERE a.id=affiliate_commissions.affiliate_id AND a.household_id=affiliate_commissions.household_id AND a.user_id=palmy.user_id())) WITH CHECK (palmy.can_access(household_id) AND EXISTS(SELECT 1 FROM palmy.affiliate_accounts a WHERE a.id=affiliate_commissions.affiliate_id AND a.household_id=affiliate_commissions.household_id AND a.user_id=palmy.user_id()));
CREATE INDEX ON palmy.affiliate_commissions(household_id,affiliate_id);
CREATE TRIGGER touch BEFORE UPDATE ON palmy.payout_destinations FOR EACH ROW EXECUTE FUNCTION palmy.touch_version();
ALTER TABLE palmy.payout_destinations ENABLE ROW LEVEL SECURITY;
ALTER TABLE palmy.payout_destinations FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_scope ON palmy.payout_destinations USING (palmy.can_access(household_id) AND EXISTS(SELECT 1 FROM palmy.affiliate_accounts a WHERE a.id=payout_destinations.affiliate_id AND a.household_id=payout_destinations.household_id AND a.user_id=palmy.user_id())) WITH CHECK (palmy.can_access(household_id) AND EXISTS(SELECT 1 FROM palmy.affiliate_accounts a WHERE a.id=payout_destinations.affiliate_id AND a.household_id=payout_destinations.household_id AND a.user_id=palmy.user_id()));
CREATE INDEX ON palmy.payout_destinations(household_id,affiliate_id);
CREATE TRIGGER touch BEFORE UPDATE ON palmy.payout_requests FOR EACH ROW EXECUTE FUNCTION palmy.touch_version();
ALTER TABLE palmy.payout_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE palmy.payout_requests FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_scope ON palmy.payout_requests USING (palmy.can_access(household_id) AND EXISTS(SELECT 1 FROM palmy.affiliate_accounts a WHERE a.id=payout_requests.affiliate_id AND a.household_id=payout_requests.household_id AND a.user_id=palmy.user_id())) WITH CHECK (palmy.can_access(household_id) AND EXISTS(SELECT 1 FROM palmy.affiliate_accounts a WHERE a.id=payout_requests.affiliate_id AND a.household_id=payout_requests.household_id AND a.user_id=palmy.user_id()));
CREATE INDEX ON palmy.payout_requests(household_id,affiliate_id);
CREATE INDEX ON palmy.payout_requests(household_id,destination_id);
CREATE TRIGGER touch BEFORE UPDATE ON palmy.promotion_submissions FOR EACH ROW EXECUTE FUNCTION palmy.touch_version();
ALTER TABLE palmy.promotion_submissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE palmy.promotion_submissions FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_scope ON palmy.promotion_submissions USING (palmy.can_access(household_id) AND EXISTS(SELECT 1 FROM palmy.affiliate_accounts a WHERE a.id=promotion_submissions.affiliate_id AND a.household_id=promotion_submissions.household_id AND a.user_id=palmy.user_id())) WITH CHECK (palmy.can_access(household_id) AND EXISTS(SELECT 1 FROM palmy.affiliate_accounts a WHERE a.id=promotion_submissions.affiliate_id AND a.household_id=promotion_submissions.household_id AND a.user_id=palmy.user_id()));
CREATE INDEX ON palmy.promotion_submissions(household_id,affiliate_id);
CREATE TRIGGER touch BEFORE UPDATE ON palmy.feedback_posts FOR EACH ROW EXECUTE FUNCTION palmy.touch_version();
ALTER TABLE palmy.feedback_posts ENABLE ROW LEVEL SECURITY;
ALTER TABLE palmy.feedback_posts FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_scope ON palmy.feedback_posts USING (palmy.can_access(household_id)) WITH CHECK (palmy.can_access(household_id));
CREATE TRIGGER touch BEFORE UPDATE ON palmy.feedback_votes FOR EACH ROW EXECUTE FUNCTION palmy.touch_version();
CREATE TRIGGER touch BEFORE UPDATE ON palmy.help_articles FOR EACH ROW EXECUTE FUNCTION palmy.touch_version();
CREATE TRIGGER touch BEFORE UPDATE ON palmy.idempotency_keys FOR EACH ROW EXECUTE FUNCTION palmy.touch_version();
ALTER TABLE palmy.idempotency_keys ENABLE ROW LEVEL SECURITY;
ALTER TABLE palmy.idempotency_keys FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_scope ON palmy.idempotency_keys USING (palmy.can_access(household_id) AND user_id=palmy.user_id()) WITH CHECK (palmy.can_access(household_id) AND user_id=palmy.user_id());
CREATE TRIGGER immutable BEFORE UPDATE OR DELETE ON palmy.audit_events FOR EACH ROW EXECUTE FUNCTION palmy.reject_mutation();
ALTER TABLE palmy.audit_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE palmy.audit_events FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_scope ON palmy.audit_events USING (palmy.can_access(household_id)) WITH CHECK (palmy.can_access(household_id));
CREATE TRIGGER touch BEFORE UPDATE ON palmy.outbox_events FOR EACH ROW EXECUTE FUNCTION palmy.touch_version();
ALTER TABLE palmy.outbox_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE palmy.outbox_events FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_scope ON palmy.outbox_events USING (palmy.can_access(household_id)) WITH CHECK (palmy.can_access(household_id));

ALTER TABLE palmy.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE palmy.users FORCE ROW LEVEL SECURITY;
CREATE POLICY self_user ON palmy.users USING(id=palmy.user_id()) WITH CHECK(id=palmy.user_id());
ALTER TABLE palmy.households ENABLE ROW LEVEL SECURITY;
ALTER TABLE palmy.households FORCE ROW LEVEL SECURITY;
CREATE POLICY own_household ON palmy.households USING(palmy.can_access(id)) WITH CHECK(palmy.is_owner(id));
ALTER TABLE palmy.feedback_votes ENABLE ROW LEVEL SECURITY;
ALTER TABLE palmy.feedback_votes FORCE ROW LEVEL SECURITY;
CREATE POLICY own_vote ON palmy.feedback_votes USING(user_id=palmy.user_id()) WITH CHECK(user_id=palmy.user_id());
ALTER TABLE palmy.help_articles ENABLE ROW LEVEL SECURITY;
ALTER TABLE palmy.help_articles FORCE ROW LEVEL SECURITY;
CREATE POLICY published_help ON palmy.help_articles FOR SELECT USING(published_at IS NOT NULL AND published_at<=now());

CREATE VIEW palmy.account_balances WITH (security_invoker=true) AS
 SELECT a.household_id,a.id account_id,coalesce(sum(l.amount) FILTER(WHERE e.state='posted'),0) balance
 FROM palmy.ledger_accounts a LEFT JOIN palmy.journal_lines l ON l.household_id=a.household_id AND l.account_id=a.id
 LEFT JOIN palmy.journal_entries e ON e.household_id=l.household_id AND e.id=l.entry_id GROUP BY a.household_id,a.id;
CREATE VIEW palmy.goal_cash_balances WITH (security_invoker=true) AS
 SELECT household_id,goal_id,wallet_id,sum(amount) reserved FROM palmy.goal_movements GROUP BY household_id,goal_id,wallet_id;
CREATE VIEW palmy.asset_positions WITH (security_invoker=true) AS
 SELECT household_id,holding_id,sum(quantity_delta) quantity,sum(cost_basis_delta) cost_basis FROM palmy.asset_trades GROUP BY household_id,holding_id;

-- Role provision is separate from this migration. Run grants after creating a NOLOGIN,
-- NOSUPERUSER,NOBYPASSRLS runtime group named palmy_app; never grant table ownership.
-- GRANT USAGE ON SCHEMA palmy TO palmy_app;
-- GRANT SELECT,INSERT,UPDATE,DELETE ON ALL TABLES IN SCHEMA palmy TO palmy_app;
-- REVOKE ALL ON palmy.pin_credentials,palmy.step_up_grants,palmy.integrations,
--   palmy.payout_destinations,palmy.calendar_feeds FROM palmy_app;
-- REVOKE INSERT,UPDATE,DELETE ON palmy.users,palmy.households,palmy.memberships,
--   palmy.help_articles,palmy.affiliate_commissions FROM palmy_app;
-- GRANT EXECUTE ON FUNCTION palmy.can_access(uuid),palmy.is_owner(uuid) TO palmy_app;
-- Identity bootstrap and secret operations use a separate narrowly scoped trusted service.
COMMIT;
