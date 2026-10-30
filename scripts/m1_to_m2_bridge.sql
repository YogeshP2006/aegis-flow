-- 1. Devices, IPs, Merchants
CREATE TABLE IF NOT EXISTS devices (
    id UUID PRIMARY KEY,
    fingerprint VARCHAR(200),
    first_seen TIMESTAMPTZ DEFAULT now(),
    reputation REAL
);

CREATE TABLE IF NOT EXISTS ips (
    id UUID PRIMARY KEY,
    ip INET,
    first_seen TIMESTAMPTZ DEFAULT now(),
    reputation REAL
);

CREATE TABLE IF NOT EXISTS merchants (
    id UUID PRIMARY KEY,
    mcc VARCHAR(4),
    name VARCHAR(200),
    reputation REAL
);

-- 2. Entity edges (for M1 contract)
CREATE TABLE IF NOT EXISTS entity_edges (
    id BIGSERIAL PRIMARY KEY,
    src_type VARCHAR(16) NOT NULL,
    src_id UUID NOT NULL,
    dst_type VARCHAR(16) NOT NULL,
    dst_id UUID NOT NULL,
    edge_type VARCHAR(32) NOT NULL,
    first_seen TIMESTAMPTZ NOT NULL DEFAULT now(),
    weight REAL NOT NULL DEFAULT 1
);

-- 3. Accounts adjustments
ALTER TABLE accounts ADD COLUMN IF NOT EXISTS id UUID;
UPDATE accounts SET id = account_id WHERE id IS NULL;
ALTER TABLE accounts ALTER COLUMN id SET DEFAULT gen_random_uuid();
CREATE UNIQUE INDEX IF NOT EXISTS idx_accounts_id ON accounts (id);
ALTER TABLE accounts ALTER COLUMN customer_id DROP NOT NULL;
ALTER TABLE accounts ALTER COLUMN account_number DROP NOT NULL;
ALTER TABLE accounts ALTER COLUMN opened_on SET DEFAULT CURRENT_DATE;

CREATE OR REPLACE FUNCTION sync_accounts_id()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.id IS NOT NULL AND NEW.account_id IS NULL THEN
        NEW.account_id := NEW.id;
    ELSIF NEW.account_id IS NOT NULL AND NEW.id IS NULL THEN
        NEW.id := NEW.account_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_sync_accounts_id ON accounts;
CREATE TRIGGER trg_sync_accounts_id
BEFORE INSERT ON accounts
FOR EACH ROW EXECUTE FUNCTION sync_accounts_id();

-- 4. Transactions adjustments
ALTER TABLE transactions ADD COLUMN IF NOT EXISTS id UUID;
UPDATE transactions SET id = txn_id WHERE id IS NULL;
ALTER TABLE transactions ALTER COLUMN id SET DEFAULT gen_random_uuid();
CREATE UNIQUE INDEX IF NOT EXISTS idx_transactions_id ON transactions (id);

ALTER TABLE transactions ADD COLUMN IF NOT EXISTS ts TIMESTAMPTZ;
UPDATE transactions SET ts = occurred_at WHERE ts IS NULL;
ALTER TABLE transactions ALTER COLUMN ts SET DEFAULT now();

ALTER TABLE transactions ADD COLUMN IF NOT EXISTS merchant_id UUID;
ALTER TABLE transactions ADD COLUMN IF NOT EXISTS ip_id UUID;

ALTER TABLE transactions ALTER COLUMN direction DROP NOT NULL;
ALTER TABLE transactions ALTER COLUMN direction SET DEFAULT 'debit';

ALTER TABLE transactions ALTER COLUMN external_ref DROP NOT NULL;
ALTER TABLE transactions ALTER COLUMN external_ref SET DEFAULT gen_random_uuid()::text;

ALTER TABLE transactions DROP CONSTRAINT IF EXISTS transactions_channel_check;
ALTER TABLE transactions ADD CONSTRAINT transactions_channel_check 
    CHECK (channel::text = ANY (ARRAY['card', 'wire', 'upi', 'ach', 'atm', 'transfer', 'wallet']));

ALTER TABLE transactions ALTER COLUMN occurred_at DROP NOT NULL;
ALTER TABLE transactions ALTER COLUMN occurred_at SET DEFAULT now();

CREATE OR REPLACE FUNCTION sync_transactions_id()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.id IS NOT NULL AND NEW.txn_id IS NULL THEN
        NEW.txn_id := NEW.id;
    ELSIF NEW.txn_id IS NOT NULL AND NEW.id IS NULL THEN
        NEW.id := NEW.txn_id;
    END IF;
    IF NEW.ts IS NOT NULL AND NEW.occurred_at IS NULL THEN
        NEW.occurred_at := NEW.ts;
    ELSIF NEW.occurred_at IS NOT NULL AND NEW.ts IS NULL THEN
        NEW.ts := NEW.occurred_at;
    END IF;
    IF NEW.direction IS NULL THEN
        NEW.direction := 'debit';
    END IF;
    IF NEW.external_ref IS NULL THEN
        NEW.external_ref := gen_random_uuid()::text;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_sync_transactions_id ON transactions;
CREATE TRIGGER trg_sync_transactions_id
BEFORE INSERT ON transactions
FOR EACH ROW EXECUTE FUNCTION sync_transactions_id();

-- 5. Ground truth labels
CREATE TABLE IF NOT EXISTS ground_truth_labels (
    transaction_id UUID PRIMARY KEY,
    is_fraud BOOLEAN NOT NULL DEFAULT FALSE,
    labeled_at TIMESTAMPTZ DEFAULT now()
);
