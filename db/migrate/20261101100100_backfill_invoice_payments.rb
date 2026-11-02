class BackfillInvoicePayments < ActiveRecord::Migration[8.1]
  # Skips invoices that already have payments, so it can run again once no
  # container still pays invoices without recording them.
  def up
    execute <<~SQL
      INSERT INTO invoice_payments (invoice_id, kind, status, amount, excess_amount, paid_on, stripe_payment_intent_id, idempotency_key, created_at, updated_at)
      SELECT id,
        CASE WHEN stripe_payment_intent_id IS NULL THEN 'manual' ELSE 'checkout' END,
        'succeeded', paid_amount, 0, paid_on, stripe_payment_intent_id, 'backfill-' || id, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
      FROM invoices
      WHERE status = 'paid'
        AND NOT EXISTS (SELECT 1 FROM invoice_payments WHERE invoice_payments.invoice_id = invoices.id)
    SQL
  end

  def down
    execute "DELETE FROM invoice_payments WHERE idempotency_key LIKE 'backfill-%'"
  end
end
