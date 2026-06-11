require "test_helper"

class InvoiceTest < ActiveSupport::TestCase
  private

  def attach_fake_pdf(invoice)
    invoice.pdf.attach io: StringIO.new("%PDF-1.4 fake"), filename: "invoice.pdf", content_type: "application/pdf"
  end

  def attach_fake_ubl(invoice)
    invoice.ubl_xml.attach io: StringIO.new("<Invoice/>"), filename: "invoice.xml", content_type: "application/xml"
  end

  def attach_fake_deliverables(invoice)
    attach_fake_pdf invoice
    attach_fake_ubl invoice
  end

  public
  test "validates required fields" do
    invoice = Invoice.new(client: clients(:acme), tax_rate: 0, subtotal: 0)
    assert_not invoice.valid?
    assert invoice.errors[:locale].any?
    assert invoice.errors[:issue_date].any?
    assert invoice.errors[:due_date].any?
  end

  test "invoice_number must be unique" do
    existing = invoices(:acme_january)
    duplicate = Invoice.new(
      client: clients(:fuji),
      invoice_number: existing.invoice_number,
      locale: :en,
      billing_month: Date.current.beginning_of_month,
      issue_date: Date.current,
      due_date: Date.current + 30,
      tax_rate: 10,
      status: :draft
    )
    duplicate.line_items.build(item_type: "Service", description: "Test", quantity: 1, unit_price: 10000, amount: 10000)
    assert_not duplicate.valid?
    assert duplicate.errors[:invoice_number].any?
  end

  test "status enum" do
    assert invoices(:acme_february_draft).draft?
    assert invoices(:acme_january).paid?
    assert invoices(:sakura_january).sent?
  end

  test "recalculate_totals computes subtotal, tax, and total" do
    invoice = invoices(:acme_february_draft)
    invoice.recalculate_totals
    assert_equal 100000, invoice.subtotal
    assert_equal 10000, invoice.tax_amount
    assert_equal 110000, invoice.total
  end

  test "tax_amount uses floor (truncation)" do
    invoice = Invoice.new(tax_rate: 10, client: clients(:acme))
    item = invoice.line_items.build(
      item_type: "Service",
      description: "Test",
      quantity: 1,
      unit_price: 33333
    )
    # Line item needs its amount calculated first
    item.valid?
    invoice.recalculate_totals

    # 33333 * 10 / 100 = 3333.3 → floor → 3333
    assert_equal 33333, invoice.subtotal
    assert_equal 3333, invoice.tax_amount
    assert_equal 36666, invoice.total
  end

  test "build_from_retainer creates retainer line item" do
    client = clients(:acme)
    invoice = client.invoices.build(
      locale: :en,
      billing_month: Date.new(2026, 2, 1),
      issue_date: Date.current,
      due_date: Date.current + 30,
      tax_rate: 10
    )
    invoice.build_from_retainer

    assert_equal 3, invoice.line_items.size # 1 retainer + 1 described extra hour + 1 aggregated generic
    retainer_item = invoice.line_items.first
    assert_includes retainer_item.description, "February 2026"
    assert_equal 100000, retainer_item.unit_price
    assert_equal 1.0, retainer_item.quantity
  end

  test "build_from_retainer creates individual line items for described extra hours" do
    client = clients(:acme)
    invoice = client.invoices.build(
      locale: :en,
      billing_month: Date.new(2026, 2, 1),
      issue_date: Date.current,
      due_date: Date.current + 30,
      tax_rate: 10
    )
    invoice.build_from_retainer

    described_item = invoice.line_items.detect { it.quantity == 0.5 }
    assert described_item
    assert_includes described_item.description, "#1421"
  end

  test "build_from_retainer aggregates generic extra hours" do
    client = clients(:acme)
    invoice = client.invoices.build(
      locale: :en,
      billing_month: Date.new(2026, 2, 1),
      issue_date: Date.current,
      due_date: Date.current + 30,
      tax_rate: 10
    )
    invoice.build_from_retainer

    generic_item = invoice.line_items.detect { it.quantity == 2.0 }
    assert generic_item
    assert_equal 20000, generic_item.amount
  end

  test "build_from_retainer returns nil without active retainer" do
    retainers(:acme_active).update_columns ends_on: 1.day.ago
    client = clients(:acme)
    invoice = client.invoices.build(locale: :en, billing_month: Date.current)
    assert_nil invoice.build_from_retainer
    assert_empty invoice.line_items
  end

  test "billing_month must be unique per client" do
    existing = invoices(:acme_january)
    duplicate = Invoice.new(
      client: existing.client,
      locale: :en,
      billing_month: existing.billing_month,
      issue_date: Date.current,
      due_date: Date.current + 30,
      tax_rate: 10
    )
    duplicate.line_items.build(item_type: "Service", description: "Test", quantity: 1, unit_price: 10000, amount: 10000)
    assert_not duplicate.valid?
    assert duplicate.errors[:billing_month].any?
  end

  test "requires at least one line item" do
    invoice = Invoice.new(
      client: clients(:acme),
      locale: :en,
      billing_month: Date.current.beginning_of_month,
      issue_date: Date.current,
      due_date: Date.current + 30,
      tax_rate: 10,
      status: :draft
    )
    assert_not invoice.valid?
    assert invoice.errors[:base].include?("must have at least one line item")
  end

  test "immutable_when_frozen prevents changes on sent invoice" do
    invoice = invoices(:sakura_january)
    attach_fake_deliverables invoice
    assert invoice.sent?
    invoice.notes = "Changed notes"
    assert_not invoice.valid?
    assert invoice.errors[:base].any?
  end

  test "immutable_when_frozen allows payment field changes on sent invoice" do
    invoice = invoices(:sakura_january)
    attach_fake_deliverables invoice
    assert invoice.sent?
    invoice.status = :paid
    invoice.paid_on = Date.current
    invoice.paid_amount = invoice.total
    assert invoice.valid?
  end

  test "mark_as_paid! sets status and payment fields" do
    invoice = invoices(:sakura_january)
    attach_fake_deliverables invoice
    invoice.mark_as_paid!
    assert invoice.paid?
    assert_equal Date.current, invoice.paid_on
    assert_equal invoice.total, invoice.paid_amount
  end

  test "paid invoice requires paid_on" do
    invoice = invoices(:acme_january)
    attach_fake_deliverables invoice
    invoice.paid_on = nil
    assert_not invoice.valid?
    assert_includes invoice.errors[:paid_on], "can't be blank"
  end

  test "non-paid invoice does not require paid_on" do
    invoice = invoices(:acme_february_draft)
    assert_nil invoice.paid_on
    assert invoice.valid?
  end

  test "paid invoice rejects a future payment date" do
    invoice = invoices(:acme_january)
    attach_fake_deliverables invoice
    invoice.paid_on = Date.current + 1
    assert_not invoice.valid?
    assert_includes invoice.errors[:paid_on], "can't be in the future"
  end

  test "paid invoice rejects a payment date before the issue date" do
    invoice = invoices(:acme_january)
    attach_fake_deliverables invoice
    invoice.paid_on = invoice.issue_date - 1
    assert_not invoice.valid?
    assert_includes invoice.errors[:paid_on], "can't be earlier than the issue date"
  end

  test "paid invoice accepts a payment date on the issue date" do
    invoice = invoices(:acme_january)
    attach_fake_deliverables invoice
    invoice.paid_on = invoice.issue_date
    assert invoice.valid?
  end

  test "deliver! transitions preparing to sent with PDF and email" do
    invoice = invoices(:acme_february_draft)
    invoice.prepare_for_delivery!

    deliver_later_called = false
    fake_mail = Object.new
    fake_mail.define_singleton_method(:deliver_later) { deliver_later_called = true }

    original_render = CloudflarePdfGateway.method(:render)
    CloudflarePdfGateway.define_singleton_method(:render) { |_html| "%PDF-fake-content" }
    original_send_invoice = InvoiceMailer.method(:send_invoice)
    InvoiceMailer.define_singleton_method(:send_invoice) { |_invoice| fake_mail }

    begin
      invoice.deliver!
    ensure
      CloudflarePdfGateway.define_singleton_method(:render, original_render)
      InvoiceMailer.define_singleton_method(:send_invoice, original_send_invoice)
    end

    assert deliver_later_called, "expected deliver_later to be called on the mailer"
    assert invoice.sent?
    assert_not_nil invoice.sent_at
    assert invoice.pdf.attached?
    assert invoice.ubl_xml.attached?
  end

  test "deliver! raises InvalidStatusError for non-preparing invoice" do
    invoice = invoices(:sakura_january)

    assert_raises Invoice::InvalidStatusError do
      invoice.deliver!
    end
  end

  test "create_checkout_session! raises InvalidStatusError for paid invoice" do
    invoice = invoices(:acme_january)
    assert invoice.paid?

    assert_raises Invoice::InvalidStatusError do
      invoice.create_checkout_session!
    end
  end

  test "open scope returns draft and sent invoices" do
    open = Invoice.open
    assert_includes open, invoices(:acme_february_draft)
    assert_includes open, invoices(:sakura_january)
    assert_not_includes open, invoices(:acme_january)
  end

  test "pdf_presence_matches_status rejects PDF on draft invoice" do
    invoice = invoices(:acme_february_draft)
    assert invoice.draft?
    attach_fake_pdf invoice
    assert_not invoice.valid?
    assert invoice.errors[:pdf].any?
  end

  test "ubl_xml_presence_matches_status rejects UBL on draft invoice" do
    invoice = invoices(:acme_february_draft)
    assert invoice.draft?
    attach_fake_ubl invoice
    assert_not invoice.valid?
    assert invoice.errors[:ubl_xml].any?
  end

  test "ubl_xml_presence_matches_status requires UBL on sent invoice" do
    invoice = invoices(:sakura_january)
    attach_fake_pdf invoice
    assert_not invoice.valid?
    assert invoice.errors[:ubl_xml].any?
  end

  # --- Status transition: prepare_for_delivery! ---

  test "prepare_for_delivery! transitions draft to preparing" do
    invoice = invoices(:acme_february_draft)
    assert invoice.draft?
    invoice.prepare_for_delivery!
    assert invoice.preparing?
  end

  test "prepare_for_delivery! raises InvalidStatusError for sent invoice" do
    invoice = invoices(:sakura_january)
    assert invoice.sent?

    assert_raises Invoice::InvalidStatusError do
      invoice.prepare_for_delivery!
    end
  end

  # --- Status transition: mark_as_failed! ---

  test "mark_as_failed! transitions preparing to failed" do
    invoice = invoices(:acme_february_draft)
    invoice.prepare_for_delivery!
    assert invoice.preparing?
    invoice.mark_as_failed!
    assert invoice.failed?
  end

  test "mark_as_failed! raises InvalidStatusError for draft invoice" do
    invoice = invoices(:acme_february_draft)
    assert invoice.draft?

    assert_raises Invoice::InvalidStatusError do
      invoice.mark_as_failed!
    end
  end

  # --- Status transition: retry_delivery! ---

  test "retry_delivery! transitions failed to preparing and clears stripe_checkout_session_id" do
    invoice = invoices(:acme_february_draft)
    invoice.prepare_for_delivery!
    invoice.mark_as_failed!
    invoice.update_columns stripe_checkout_session_id: "cs_test_123"
    assert invoice.failed?

    invoice.retry_delivery!
    assert invoice.preparing?
    assert_nil invoice.stripe_checkout_session_id
  end

  test "retry_delivery! raises InvalidStatusError for sent invoice" do
    invoice = invoices(:sakura_january)
    assert invoice.sent?

    assert_raises Invoice::InvalidStatusError do
      invoice.retry_delivery!
    end
  end

  # --- Status transition: revert_to_draft! ---

  test "revert_to_draft! transitions failed to draft and clears stripe_checkout_session_id" do
    invoice = invoices(:acme_february_draft)
    invoice.prepare_for_delivery!
    invoice.mark_as_failed!
    invoice.update_columns stripe_checkout_session_id: "cs_test_456"
    assert invoice.failed?

    invoice.revert_to_draft!
    assert invoice.draft?
    assert_nil invoice.stripe_checkout_session_id
  end

  test "revert_to_draft! raises InvalidStatusError for sent invoice" do
    invoice = invoices(:sakura_january)
    assert invoice.sent?

    assert_raises Invoice::InvalidStatusError do
      invoice.revert_to_draft!
    end
  end

  # --- deliver! precondition change ---

  test "deliver! raises InvalidStatusError for draft invoice" do
    invoice = invoices(:acme_february_draft)
    assert invoice.draft?

    assert_raises Invoice::InvalidStatusError do
      invoice.deliver!
    end
  end

  # --- immutable_when_frozen for new statuses ---

  test "immutable_when_frozen prevents field changes on preparing invoice" do
    invoice = invoices(:acme_february_draft)
    invoice.prepare_for_delivery!
    assert invoice.preparing?

    invoice.notes = "Changed notes"
    assert_not invoice.valid?
    assert invoice.errors[:base].any?
  end

  test "immutable_when_frozen prevents field changes on failed invoice" do
    invoice = invoices(:acme_february_draft)
    invoice.prepare_for_delivery!
    invoice.mark_as_failed!
    assert invoice.failed?

    invoice.notes = "Changed notes"
    assert_not invoice.valid?
    assert invoice.errors[:base].any?
  end

  # --- pdf_presence_matches_status for new statuses ---

  test "pdf_presence_matches_status allows preparing invoice without PDF" do
    invoice = invoices(:acme_february_draft)
    invoice.prepare_for_delivery!
    assert invoice.preparing?
    assert_not invoice.pdf.attached?
    assert invoice.valid?
  end

  test "pdf_presence_matches_status allows failed invoice without PDF" do
    invoice = invoices(:acme_february_draft)
    invoice.prepare_for_delivery!
    invoice.mark_as_failed!
    assert invoice.failed?
    assert_not invoice.pdf.attached?
    assert invoice.valid?
  end

  # --- open scope includes new statuses ---

  test "open scope includes preparing and failed invoices" do
    invoice = invoices(:acme_february_draft)
    invoice.prepare_for_delivery!

    open = Invoice.open
    assert_includes open, invoice
    assert_includes open, invoices(:sakura_january)
    assert_not_includes open, invoices(:acme_january)

    invoice.mark_as_failed!
    open = Invoice.open
    assert_includes open, invoice
  end

  # Live updates are handled declaratively by `broadcasts_refreshes` (Turbo 8
  # page refreshes), which is framework-tested. The user-facing outcome — the
  # page reflecting a change — is covered in test/system/invoice_payments_test.rb.
end
