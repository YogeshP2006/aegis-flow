import psycopg

SQL = """
CREATE OR REPLACE FUNCTION sync_accounts_id()
RETURNS TRIGGER AS $f$
BEGIN
    IF NEW.id IS NOT NULL THEN
        NEW.account_id := NEW.id;
    ELSIF NEW.account_id IS NOT NULL THEN
        NEW.id := NEW.account_id;
    END IF;
    RETURN NEW;
END;
$f$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sync_transactions_id()
RETURNS TRIGGER AS $f$
BEGIN
    IF NEW.id IS NOT NULL THEN
        NEW.txn_id := NEW.id;
    ELSIF NEW.txn_id IS NOT NULL THEN
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
$f$ LANGUAGE plpgsql;
"""

with psycopg.connect("postgresql://aegis:aegis_dev_2026@localhost:5432/aegisflow") as conn:
    conn.execute(SQL)
    conn.commit()

print("Triggers updated successfully!")
