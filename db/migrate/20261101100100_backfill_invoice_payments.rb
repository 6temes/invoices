class BackfillInvoicePayments < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      INSERT INTO invoice_payments (invoice_id, kind, status, amount, excess_amount, stripe_payment_intent_id, idempotency_key, created_at, updated_at)
      SELECT id,
        CASE WHEN stripe_payment_intent_id IS NULL THEN 'manual' ELSE 'checkout' END,
        'succeeded', paid_amount, 0, stripe_payment_intent_id, 'backfill-' || id, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
      FROM invoices
      WHERE status = 'paid'
    SQL
  end

  def down
    execute "DELETE FROM invoice_payments WHERE idempotency_key LIKE 'backfill-%'"
  end
end
