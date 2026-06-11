require "test_helper"

class InvoiceGenerationJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "creates invoices for clients with active retainers and queues them for delivery" do
    # March 1 → bills for February. Acme already has a Feb draft, so only sakura + fuji are new.
    travel_to Date.new(2026, 3, 1) do
      assert_difference "Invoice.count", 2 do
        assert_enqueued_jobs 2, only: InvoiceDeliveryJob do
          InvoiceGenerationJob.new.perform
        end
      end

      invoice = Invoice.order(:id).last
      # Must be moved past draft, otherwise InvoiceDeliveryJob#deliver! raises
      # InvalidStatusError and is silently discarded — invoices never get sent.
      assert invoice.preparing?
      assert_equal Date.new(2026, 2, 1), invoice.billing_month
      assert invoice.line_items.any?
    end
  end

  test "skips clients without active retainers" do
    Retainer.update_all ends_on: 1.day.ago

    assert_no_difference "Invoice.count" do
      InvoiceGenerationJob.new.perform
    end
  end

  test "is idempotent — skips existing invoices for same client and month" do
    travel_to Date.new(2026, 3, 1) do
      InvoiceGenerationJob.new.perform

      assert_no_difference "Invoice.count" do
        InvoiceGenerationJob.new.perform
      end
    end
  end

  test "increments business next_invoice_number" do
    business = businesses(:default)
    starting = business.next_invoice_number

    travel_to Date.new(2026, 3, 1) do
      InvoiceGenerationJob.new.perform
    end

    # Acme is skipped (already has Feb invoice), so only sakura + fuji get numbers
    assert_equal starting + 2, business.reload.next_invoice_number
  end
end
