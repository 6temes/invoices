require "test_helper"

class InvoiceTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

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

  test "a backdated manual payment is recorded on the date it was paid" do
    invoice = invoices(:sakura_january)
    attach_fake_deliverables invoice

    invoice.mark_as_paid! paid_on: Date.new(2026, 2, 10)

    assert_equal Date.new(2026, 2, 10), invoice.payments.sole.paid_on
  end

  test "amount_due is what the payments have not covered yet" do
    assert_equal 247_500, invoices(:sakura_january).amount_due

    invoices(:sakura_january).paid_amount = 100_000
    assert_equal 147_500, invoices(:sakura_january).amount_due

    assert_equal 0, invoices(:acme_january).amount_due
  end

  # --- Reminder tracking ---

  test "can_send_reminder? is true only for sent invoices" do
    assert invoices(:sakura_january).can_send_reminder? # sent

    assert_not invoices(:acme_february_draft).can_send_reminder? # draft
    assert_not invoices(:acme_january).can_send_reminder? # paid

    invoice = invoices(:acme_february_draft)
    invoice.prepare_for_delivery!
    assert_not invoice.can_send_reminder? # preparing

    invoice.mark_as_failed!
    assert_not invoice.can_send_reminder? # failed
  end

  test "record_reminder! sets reminded_at and increments the count" do
    invoice = invoices(:sakura_january)
    attach_fake_deliverables invoice
    assert_nil invoice.reminded_at
    assert_equal 0, invoice.reminders_count

    invoice.record_reminder!
    assert_not_nil invoice.reminded_at
    assert_equal 1, invoice.reminders_count

    invoice.record_reminder!
    assert_equal 2, invoice.reminders_count
  end

  # --- Receipt on payment ---

  test "mark_as_paid! enqueues a receipt email once and sets payment fields" do
    invoice = invoices(:sakura_january)
    attach_fake_deliverables invoice

    assert_enqueued_email_with InvoiceMailer, :send_receipt, args: [ invoice ] do
      invoice.mark_as_paid!
    end

    assert invoice.paid?
    assert_equal invoice.total, invoice.paid_amount
    assert_equal Date.current, invoice.paid_on
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

  test "deliver! creates a Checkout session for a stripe client" do
    invoice = invoices(:acme_february_draft)
    invoice.update! client: clients(:sakura)
    invoice.prepare_for_delivery!
    CloudflarePdfGateway.stubs(:render).returns("%PDF-fake-content")
    InvoiceMailer.stubs(:send_invoice).returns(stub(deliver_later: true))
    Stripe::Customer.stubs(:retrieve).returns(Stripe::Customer.construct_from(id: "cus_test_sakura123"))
    Stripe::Checkout::Session.expects(:create).returns(Stripe::Checkout::Session.construct_from(id: "cs_on_delivery"))

    invoice.deliver!

    assert invoice.sent?
    assert_equal "cs_on_delivery", invoice.reload.stripe_checkout_session_id
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

  test "issued excludes drafts and keeps every other status" do
    invoices(:sakura_january).update_column :status, "failed"

    assert_equal [ 145, 146 ], Invoice.issued.order(:invoice_number).pluck(:invoice_number)
  end

  test "for_year selects by issue date, not billing month" do
    invoices(:acme_january).update_columns billing_month: Date.new(2025, 12), issue_date: Date.new(2026, 1, 5)

    assert_includes Invoice.for_year(2026), invoices(:acme_january)
    assert_not_includes Invoice.for_year(2025), invoices(:acme_january)
  end
  # --- Payment races and Stripe Checkout reconciliation ---

  test "mark_as_paid! raises on an invoice another caller already paid, and sends no second receipt" do
    invoice = invoices(:sakura_january)
    attach_fake_deliverables invoice
    stale = Invoice.find invoice.id

    invoice.mark_as_paid!

    assert_no_enqueued_emails do
      assert_raises(Invoice::InvalidStatusError) { stale.mark_as_paid! }
    end
  end

  test "create_checkout_session! leaves the payment methods to the Stripe Dashboard" do
    invoice = invoices(:sakura_january)
    attach_fake_deliverables invoice
    Stripe::Customer.stubs(:retrieve).returns(Stripe::Customer.construct_from(id: "cus_test_sakura123"))
    Stripe::Checkout::Session.expects(:create)
      .with(Not(has_key(:payment_method_types)))
      .returns(Stripe::Checkout::Session.construct_from(id: "cs_any_method"))

    invoice.create_checkout_session!

    assert_equal "cs_any_method", invoice.reload.stripe_checkout_session_id
  end

  test "create_checkout_session! charges what is still due, and refuses when nothing is" do
    invoice = invoices(:sakura_january)
    attach_fake_deliverables invoice
    invoice.update_columns paid_amount: 100_000
    Stripe::Customer.stubs(:retrieve).returns(Stripe::Customer.construct_from(id: "cus_test_sakura123"))
    Stripe::Checkout::Session.expects(:create)
      .with { it[:line_items].sole[:price_data][:unit_amount] == 147_500 }
      .returns(Stripe::Checkout::Session.construct_from(id: "cs_remaining"))

    invoice.create_checkout_session!

    invoice.update_columns paid_amount: invoice.total
    assert_raises(Invoice::InvalidStatusError) { invoice.create_checkout_session! }
  end

  test "the PDF lists payments received and labels the last row as the amount due" do
    invoice = invoices(:sakura_january)
    invoice.update_columns paid_amount: 100_000

    html = Nokogiri::HTML(ApplicationController.render(partial: "invoices/pdf_template", locals: { invoice:, business: businesses(:default) }))

    assert_includes html.at_css(".totals").text, "−¥100,000"
    assert_equal [ "請求金額", "¥147,500" ], html.css(".grand-total span").map { it.text.strip }
  end

  test "the PDF shows credit applied apart from later payments" do
    invoice = invoices(:sakura_january)
    invoice.payments.create! kind: :credit, amount: 47_500, stripe_payment_intent_id: "pi_credit"
    invoice.update_columns paid_amount: 47_500

    html = Nokogiri::HTML(ApplicationController.render(partial: "invoices/pdf_template", locals: { invoice:, business: businesses(:default) }))
    rows = html.css(".totals-row").map { it.css("span").map { it.text.strip } }

    assert_includes rows, [ "ご入金残高より充当", "−¥47,500" ]
    assert_not_includes rows.map(&:first), "お支払い"
    assert_equal [ "請求金額", "¥200,000" ], html.css(".grand-total span").map { it.text.strip }
  end

  test "create_checkout_session! keeps the session that paid while the new one was being created" do
    invoice = invoices(:sakura_january)
    attach_fake_deliverables invoice
    Stripe::Customer.stubs(:retrieve).returns(Stripe::Customer.construct_from(id: "cus_test_sakura123"))
    Stripe::Checkout::Session.stubs(:create).with do
      Invoice.where(id: invoice.id).update_all status: "paid", stripe_checkout_session_id: "cs_paid"
    end.returns(Stripe::Checkout::Session.construct_from(id: "cs_late"))

    assert_raises(Invoice::InvalidStatusError) { invoice.create_checkout_session! }
    assert_equal "cs_paid", invoice.reload.stripe_checkout_session_id
  end

  test "a paid checkout session marks the invoice paid and sends one receipt" do
    invoice = invoices(:sakura_january)
    attach_fake_deliverables invoice

    assert_enqueued_emails 1 do
      Invoice.apply_checkout_session paid_session(invoice, id: "cs_paid", payment_intent: "pi_paid")
    end

    invoice.reload
    assert invoice.paid?
    assert_equal invoice.total, invoice.paid_amount
    assert_equal "cs_paid", invoice.stripe_checkout_session_id
    assert_equal "pi_paid", invoice.payments.sole.stripe_payment_intent_id
  end

  test "the same paid session applied twice pays once, even from a stale copy" do
    invoice = invoices(:sakura_january)
    attach_fake_deliverables invoice
    stale = Invoice.find invoice.id
    session = paid_session(invoice, id: "cs_twice")

    assert_enqueued_emails 1 do
      invoice.apply_checkout_session session
      assert_no_error_reported { stale.apply_checkout_session session }
    end
    assert invoice.reload.paid?
  end

  test "a bank transfer that settles just after a manual mark is kept as nothing and sent back to the client's bank" do
    invoice = invoices(:sakura_january)
    attach_deliverables invoice
    invoice.mark_as_paid!
    stub_payment_method "pi_transfer", "customer_balance"
    Stripe::Refund.expects(:create)
      .with({ payment_intent: "pi_transfer", amount: invoice.total, instructions_email: invoice.client.email }, anything)
      .returns(Stripe::Refund.construct_from(id: "re_transfer"))

    assert_no_enqueued_emails do
      assert_no_error_reported do
        Invoice.apply_checkout_session paid_session(invoice, id: "cs_late", payment_intent: "pi_transfer")
      end
    end

    payment = invoice.payments.find_by!(stripe_payment_intent_id: "pi_transfer")
    assert_equal [ 0, invoice.total, "re_transfer" ], [ payment.amount, payment.excess_amount, payment.stripe_refund_id ]
    assert_equal invoice.total, invoice.reload.paid_amount
  end

  test "a payment below the amount due is recorded and leaves the invoice sent" do
    invoice = invoices(:sakura_january)
    attach_deliverables invoice

    assert_no_enqueued_emails do
      Invoice.apply_checkout_session paid_session(invoice, payment_intent: "pi_part", amount_total: 100_000)
    end

    invoice.reload
    assert invoice.sent?
    assert_equal 100_000, invoice.paid_amount
    assert_equal 147_500, invoice.amount_due
  end

  test "a card payment above the amount due keeps what is owed and refunds the rest to the card" do
    invoice = invoices(:sakura_january)
    attach_deliverables invoice
    stub_payment_method "pi_over", "card"
    Stripe::Refund.expects(:create)
      .with({ payment_intent: "pi_over", amount: 2_500 }, has_entry(idempotency_key: regexp_matches(/\Aexcess-\d+\z/)))
      .returns(Stripe::Refund.construct_from(id: "re_over"))

    assert_enqueued_emails 1 do
      Invoice.apply_checkout_session paid_session(invoice, payment_intent: "pi_over", amount_total: invoice.total + 2_500)
    end

    payment = invoice.payments.sole
    assert_equal [ invoice.total, 2_500, "re_over" ], [ payment.amount, payment.excess_amount, payment.stripe_refund_id ]
    assert invoice.reload.paid?
  end

  test "a failed refund raises, keeps the excess on the row and is retried from it" do
    invoice = invoices(:sakura_january)
    attach_deliverables invoice
    stub_payment_method "pi_over", "card"
    Stripe::Refund.stubs(:create).raises(Stripe::APIConnectionError.new("timeout")).then.returns(Stripe::Refund.construct_from(id: "re_retry"))
    session = paid_session(invoice, payment_intent: "pi_over", amount_total: invoice.total + 2_500)

    assert_raises(Stripe::APIConnectionError) { Invoice.apply_checkout_session session }
    payment = invoice.payments.sole
    assert_equal [ 2_500, nil ], [ payment.excess_amount, payment.stripe_refund_id ]

    Invoice.apply_checkout_session session
    assert_equal "re_retry", payment.reload.stripe_refund_id
    assert_equal 1, invoice.payments.count
  end

  test "marking a partly paid invoice paid records the remainder and cancels the transfer still awaiting funds" do
    invoice = invoices(:sakura_january)
    attach_deliverables invoice
    Invoice.apply_checkout_session paid_session(invoice, id: "cs_part", payment_intent: "pi_part", amount_total: 100_000)
    invoice.update_columns stripe_checkout_session_id: "cs_transfer"
    Stripe::Checkout::Session.stubs(:retrieve).with("cs_transfer").returns(unpaid_session(invoice, id: "cs_transfer", payment_intent: "pi_transfer"))
    Stripe::PaymentIntent.stubs(:retrieve).with("pi_transfer").returns(payment_intent(id: "pi_transfer", status: "requires_action"))
    Stripe::PaymentIntent.expects(:cancel).with("pi_transfer")

    invoice.reload.mark_as_paid!

    assert invoice.reload.paid?
    assert_equal [ 100_000, 147_500 ], invoice.payments.order(:id).pluck(:amount)
    assert_equal "manual", invoice.payments.order(:id).last.kind
  end

  test "marking an invoice paid expires its open Checkout session, and a Stripe failure there does not stop it" do
    invoice = invoices(:sakura_january)
    attach_deliverables invoice
    invoice.update_columns stripe_checkout_session_id: "cs_open"
    Stripe::Checkout::Session.stubs(:retrieve).with("cs_open").returns(checkout_session(id: "cs_open", status: "open"))
    Stripe::Checkout::Session.expects(:expire).with("cs_open").raises(Stripe::InvalidRequestError.new("already expired", nil))

    assert_error_reported(Stripe::InvalidRequestError) { invoice.mark_as_paid! }
    assert invoice.reload.paid?
  end

  test "marking an invoice paid that Stripe already paid records the Stripe payment, not a manual one" do
    invoice = invoices(:sakura_january)
    attach_deliverables invoice
    invoice.update_columns stripe_checkout_session_id: "cs_paid"
    Stripe::Checkout::Session.stubs(:retrieve).with("cs_paid").returns(paid_session(invoice, id: "cs_paid", payment_intent: "pi_paid"))
    Stripe::Refund.expects(:create).never

    assert_enqueued_emails 1 do
      invoice.mark_as_paid!
      Invoice.apply_checkout_session paid_session(invoice, id: "cs_paid", payment_intent: "pi_paid")
    end

    assert invoice.reload.paid?
    assert_equal [ "checkout", invoice.total ], [ invoice.payments.sole.kind, invoice.paid_amount ]
  end

  test "a paid session paying while another session is pending releases the pending one" do
    invoice = invoices(:sakura_january)
    attach_deliverables invoice
    invoice.update_columns stripe_checkout_session_id: "cs_other"
    Stripe::Checkout::Session.stubs(:retrieve).with("cs_other").returns(checkout_session(id: "cs_other", status: "open"))
    Stripe::Checkout::Session.expects(:expire).with("cs_other")

    Invoice.apply_checkout_session paid_session(invoice, id: "cs_paying")

    assert invoice.reload.paid?
  end

  test "a paid session that is the stored one releases nothing" do
    invoice = invoices(:sakura_january)
    attach_deliverables invoice
    invoice.update_columns stripe_checkout_session_id: "cs_paying"
    Stripe::Checkout::Session.expects(:retrieve).never

    Invoice.apply_checkout_session paid_session(invoice, id: "cs_paying")

    assert invoice.reload.paid?
  end

  test "a paid session for an invoice paid without recorded payments is reported, not refunded" do
    invoice = invoices(:sakura_january)
    attach_deliverables invoice
    invoice.update_columns status: "paid", paid_on: Date.current, paid_amount: invoice.total
    Stripe::Refund.expects(:create).never

    assert_error_reported(Invoice::Payable::UnrecordedPaymentError) do
      Invoice.apply_checkout_session paid_session(invoice)
    end

    assert_empty invoice.payments
    assert_equal invoice.total, invoice.reload.paid_amount
  end

  test "a completed session still awaiting a delayed payment changes nothing" do
    invoice = invoices(:sakura_january)
    invoice.update_columns stripe_checkout_session_id: "cs_konbini"

    %w[ requires_action processing ].each do |status|
      assert_no_error_reported do
        assert_no_enqueued_emails do
          outcome = Invoice.apply_checkout_session unpaid_session(invoice, id: "cs_konbini"), payment_intent: payment_intent(status:)
          assert_equal :pending, outcome
        end
      end
    end

    invoice.reload
    assert invoice.sent?
    assert_equal "cs_konbini", invoice.stripe_checkout_session_id
  end

  test "a pending delayed payment becomes the stored session" do
    invoice = invoices(:sakura_january)
    attach_fake_deliverables invoice
    invoice.update_columns stripe_checkout_session_id: "cs_other_tab"

    Invoice.apply_checkout_session unpaid_session(invoice, id: "cs_konbini"), payment_intent: payment_intent(status: "requires_action")

    assert_equal "cs_konbini", invoice.reload.stripe_checkout_session_id
  end

  test "a pending delayed payment leaves an invoice that is not sent alone" do
    invoice = invoices(:sakura_january)
    invoice.update_columns status: "preparing", stripe_checkout_session_id: "cs_other_tab"

    Invoice.apply_checkout_session unpaid_session(invoice, id: "cs_konbini"), payment_intent: payment_intent(status: "requires_action")

    assert_equal "cs_other_tab", invoice.reload.stripe_checkout_session_id
  end

  test "a completed unpaid session without its payment intent is treated as pending" do
    invoice = invoices(:sakura_january)
    invoice.update_columns stripe_checkout_session_id: "cs_konbini"

    assert_no_error_reported do
      assert_equal :pending, Invoice.apply_checkout_session(unpaid_session(invoice, id: "cs_konbini"))
    end
    assert_equal "cs_konbini", invoice.reload.stripe_checkout_session_id
  end

  test "a delayed payment that settles later pays once and sends one receipt" do
    invoice = invoices(:sakura_january)
    attach_fake_deliverables invoice
    invoice.update_columns stripe_checkout_session_id: "cs_konbini"

    assert_enqueued_emails 1 do
      Invoice.apply_checkout_session unpaid_session(invoice, id: "cs_konbini"), payment_intent: payment_intent(status: "requires_action")
      Invoice.apply_checkout_session paid_session(invoice, id: "cs_konbini", payment_intent: "pi_konbini")
      Invoice.apply_checkout_session paid_session(invoice, id: "cs_konbini", payment_intent: "pi_konbini")
    end

    invoice.reload
    assert invoice.paid?
    assert_equal "pi_konbini", invoice.payments.sole.stripe_payment_intent_id
  end

  test "a settled payment seen before its completion pays once" do
    invoice = invoices(:sakura_january)
    attach_fake_deliverables invoice
    invoice.update_columns stripe_checkout_session_id: "cs_konbini"

    assert_enqueued_emails 1 do
      Invoice.apply_checkout_session paid_session(invoice, id: "cs_konbini", payment_intent: "pi_konbini")
      assert_no_error_reported do
        Invoice.apply_checkout_session unpaid_session(invoice, id: "cs_konbini"), payment_intent: payment_intent(status: "requires_action")
      end
    end
    assert invoice.reload.paid?
  end

  test "a failed delayed payment clears the stored session so the client can pay again" do
    invoice = invoices(:sakura_january)
    attach_fake_deliverables invoice

    %w[ requires_payment_method canceled ].each do |status|
      invoice.update_columns stripe_checkout_session_id: "cs_konbini"

      assert_no_error_reported do
        assert_no_enqueued_emails do
          Invoice.apply_checkout_session unpaid_session(invoice, id: "cs_konbini"), payment_intent: payment_intent(status:)
        end
      end

      invoice.reload
      assert invoice.sent?
      assert_nil invoice.stripe_checkout_session_id
    end
  end

  test "a failed delayed payment leaves a newer session alone" do
    invoice = invoices(:sakura_january)
    invoice.update_columns stripe_checkout_session_id: "cs_retry"

    Invoice.apply_checkout_session unpaid_session(invoice, id: "cs_konbini"), payment_intent: payment_intent(status: "requires_payment_method")

    assert_equal "cs_retry", invoice.reload.stripe_checkout_session_id
  end

  test "a failed delayed payment leaves an invoice that is not sent alone" do
    invoice = invoices(:sakura_january)
    invoice.update_columns status: "preparing", stripe_checkout_session_id: "cs_konbini"

    Invoice.apply_checkout_session unpaid_session(invoice, id: "cs_konbini"), payment_intent: payment_intent(status: "requires_payment_method")

    assert_equal "cs_konbini", invoice.reload.stripe_checkout_session_id
  end

  test "a completed session with no payment required is reported" do
    invoice = invoices(:sakura_january)

    assert_error_reported(Invoice::UnpaidCheckoutError) do
      Invoice.apply_checkout_session paid_session(invoice, payment_status: "no_payment_required")
    end
    assert invoice.reload.sent?
  end

  test "reconcile_checkout_session fetches the payment intent only for a completed unpaid session" do
    invoice = invoices(:sakura_january)
    attach_fake_deliverables invoice
    invoice.update_columns stripe_checkout_session_id: "cs_konbini"
    Stripe::PaymentIntent.expects(:retrieve).with("pi_konbini").returns(payment_intent(status: "requires_payment_method"))

    Invoice.reconcile_checkout_session unpaid_session(invoice, id: "cs_konbini", payment_intent: "pi_konbini")

    assert_nil invoice.reload.stripe_checkout_session_id
  end

  test "reconcile_checkout_session makes no extra Stripe call for a paid, open or expired session" do
    invoice = invoices(:sakura_january)
    attach_fake_deliverables invoice
    Stripe::PaymentIntent.expects(:retrieve).never

    Invoice.reconcile_checkout_session checkout_session(id: "cs_open", status: "open", metadata: { invoice_id: invoice.id.to_s })
    Invoice.reconcile_checkout_session expired_session(invoice, id: "cs_old")
    assert_equal :paid, Invoice.reconcile_checkout_session(paid_session(invoice, id: "cs_paid"))
  end

  test "a session in another currency is reported, not recorded" do
    invoice = invoices(:sakura_january)

    assert_error_reported(Invoice::CurrencyMismatchError) do
      Invoice.apply_checkout_session paid_session(invoice, currency: "usd")
    end
    assert invoice.reload.sent?
    assert_empty invoice.payments
  end

  test "a session without an invoice, or naming an unknown one, is reported" do
    assert_error_reported(Invoice::MissingMetadataError) do
      Invoice.apply_checkout_session checkout_session(id: "cs_orphan", status: "complete", metadata: {})
    end
    assert_error_reported(Invoice::InvoiceNotFoundError) do
      Invoice.apply_checkout_session checkout_session(id: "cs_unknown", status: "complete", metadata: { invoice_id: "0" })
    end
  end

  test "a paid session for a draft invoice raises" do
    assert_raises Invoice::InvalidStatusError do
      Invoice.apply_checkout_session paid_session(invoices(:acme_february_draft))
    end
  end

  test "an expired session clears the stored id only when it is the current one" do
    invoice = invoices(:sakura_january)
    attach_fake_deliverables invoice
    invoice.update_columns stripe_checkout_session_id: "cs_new"

    Invoice.apply_checkout_session expired_session(invoice, id: "cs_old")
    assert_equal "cs_new", invoice.reload.stripe_checkout_session_id

    Invoice.apply_checkout_session expired_session(invoice, id: "cs_new")
    assert_nil invoice.reload.stripe_checkout_session_id
  end

  test "an expired session leaves a paid invoice alone" do
    invoice = invoices(:acme_january)
    attach_fake_deliverables invoice
    invoice.update_columns stripe_checkout_session_id: "cs_paid_earlier"

    assert_no_enqueued_emails do
      Invoice.apply_checkout_session expired_session(invoice, id: "cs_paid_earlier")
    end
    assert_equal "cs_paid_earlier", invoice.reload.stripe_checkout_session_id
  end

  test "an expired session leaves an invoice that is not sent alone" do
    invoice = invoices(:sakura_january)
    invoice.update_columns status: "preparing", stripe_checkout_session_id: "cs_current"

    Invoice.apply_checkout_session expired_session(invoice, id: "cs_current")

    assert_equal "cs_current", invoice.reload.stripe_checkout_session_id
  end

  test "an open session changes nothing" do
    invoice = invoices(:sakura_january)
    invoice.update_columns stripe_checkout_session_id: "cs_open"

    assert_no_error_reported do
      Invoice.apply_checkout_session checkout_session(id: "cs_open", status: "open", metadata: { invoice_id: invoice.id.to_s })
    end
    invoice.reload
    assert invoice.sent?
    assert_equal "cs_open", invoice.stripe_checkout_session_id
  end

  test "a cash balance that covers the invoice pays it at delivery" do
    invoice = preparing_stripe_invoice
    stub_cash_balance 300_000
    Stripe::PaymentIntent.expects(:create)
      .with(has_entries(amount: 110_000, currency: "jpy", customer: "cus_test_sakura123", confirm: true,
        payment_method_data: { type: "customer_balance" }), anything)
      .returns(payment_intent(status: "succeeded", id: "pi_credit"))
    Stripe::Checkout::Session.expects(:create).never
    InvoiceMailer.expects(:send_receipt).never

    deliver invoice

    assert invoice.paid?
    assert_equal Date.current, invoice.paid_on
    assert_equal 0, invoice.amount_due
    credit = invoice.payments.credit.sole
    assert credit.succeeded?
    assert_equal [ 110_000, "pi_credit" ], [ credit.amount, credit.stripe_payment_intent_id ]
  end

  test "credit leaves at least the minimum charge due" do
    invoice = preparing_stripe_invoice
    stub_cash_balance 109_980
    Stripe::PaymentIntent.expects(:create).with(has_entry(amount: 109_950), anything)
      .returns(payment_intent(status: "succeeded", id: "pi_credit"))
    stub_checkout_session

    deliver invoice

    assert invoice.sent?
    assert_equal 50, invoice.amount_due
  end

  test "a balance below the minimum charge draws nothing" do
    [ 0, 30 ].each do |balance|
      invoice = preparing_stripe_invoice
      stub_cash_balance balance
      Stripe::PaymentIntent.expects(:create).never
      stub_checkout_session

      deliver invoice

      assert invoice.sent?
      assert_empty invoice.payments
      invoice.update_columns status: "draft", sent_at: nil
      invoice.pdf.detach
      invoice.ubl_xml.detach
    end
  end

  test "full credit on a future-dated invoice is paid on its issue date" do
    invoice = invoices(:acme_february_draft)
    invoice.update! client: clients(:sakura), issue_date: Date.current + 10, due_date: Date.current + 40
    invoice.prepare_for_delivery!
    stub_cash_balance 300_000
    Stripe::PaymentIntent.stubs(:create).returns(payment_intent(status: "succeeded", id: "pi_credit"))

    deliver invoice

    assert invoice.paid?
    assert_equal invoice.issue_date, invoice.paid_on
  end

  test "a pending credit is replayed with its own amount and key" do
    invoice = preparing_stripe_invoice
    pending = invoice.payments.create!(kind: :credit, status: :pending, amount: 40_000, idempotency_key: "invoice-payment-replay")
    Stripe::Customer.expects(:retrieve).with(id: "cus_test_sakura123", expand: [ "cash_balance" ]).never
    Stripe::PaymentIntent.expects(:create)
      .with(has_entries(amount: 40_000, metadata: { invoice_id: invoice.id, invoice_payment_id: pending.id }),
        { idempotency_key: "invoice-payment-replay" })
      .returns(payment_intent(status: "succeeded", id: "pi_credit"))
    stub_checkout_session

    deliver invoice

    assert pending.reload.succeeded?
    assert_equal 70_000, invoice.amount_due
  end

  test "a pending credit older than a day is found by listing instead of replayed" do
    invoice = preparing_stripe_invoice
    pending = invoice.payments.create!(kind: :credit, status: :pending, amount: 40_000, idempotency_key: "invoice-payment-old")
    pending.update_columns created_at: 2.days.ago
    found = Stripe::PaymentIntent.construct_from(id: "pi_found", status: "succeeded", metadata: { invoice_payment_id: pending.id.to_s })
    other = Stripe::PaymentIntent.construct_from(id: "pi_other", status: "succeeded", metadata: {})
    Stripe::PaymentIntent.expects(:list).with(has_entries(customer: "cus_test_sakura123", created: { gte: pending.created_at.to_i }))
      .returns(Stripe::ListObject.construct_from(object: "list", data: [ other, found ], has_more: false))
    Stripe::PaymentIntent.expects(:create).never
    stub_checkout_session

    deliver invoice

    assert_equal "pi_found", pending.reload.stripe_payment_intent_id
    assert pending.succeeded?
  end

  test "a pending credit older than a day that Stripe never saw starts over" do
    invoice = preparing_stripe_invoice
    pending = invoice.payments.create!(kind: :credit, status: :pending, amount: 40_000, idempotency_key: "invoice-payment-lost")
    pending.update_columns created_at: 2.days.ago
    Stripe::PaymentIntent.stubs(:list).returns(Stripe::ListObject.construct_from(object: "list", data: [], has_more: false))
    stub_cash_balance 20_000
    Stripe::PaymentIntent.expects(:create).with(has_entry(amount: 20_000), anything)
      .returns(payment_intent(status: "succeeded", id: "pi_credit"))
    stub_checkout_session

    deliver invoice

    assert_not InvoicePayment.exists?(pending.id)
    assert_equal 20_000, invoice.payments.credit.sole.amount
  end

  test "a balance spent since it was read is released and drawn again for less" do
    invoice = preparing_stripe_invoice
    stub_cash_balance 100_000, 60_000
    Stripe::PaymentIntent.expects(:create).with(has_entry(amount: 100_000), anything)
      .returns(payment_intent(status: "requires_action", id: "pi_short"))
    Stripe::PaymentIntent.expects(:cancel).with("pi_short")
    Stripe::PaymentIntent.expects(:create).with(has_entry(amount: 60_000), anything)
      .returns(payment_intent(status: "succeeded", id: "pi_credit"))
    stub_checkout_session

    deliver invoice

    assert_equal [ 60_000 ], invoice.payments.map(&:amount)
    assert_equal 50_000, invoice.amount_due
  end

  test "retrying a failed delivery keeps the credit it drew" do
    invoice = failed_invoice_with_credit 50_000
    invoice.retry_delivery!
    Stripe::Customer.expects(:retrieve).with(id: "cus_test_sakura123", expand: [ "cash_balance" ]).never
    Stripe::PaymentIntent.expects(:create).never
    stub_checkout_session

    deliver invoice

    assert_equal 60_000, invoice.amount_due
    assert_equal [ 50_000 ], invoice.payments.map(&:amount)
  end

  test "reverting to draft keeps the credit for the next delivery" do
    invoice = failed_invoice_with_credit 50_000
    Stripe::Refund.expects(:create).never

    invoice.revert_to_draft!

    assert invoice.draft?
    assert_equal 50_000, invoice.payments.credit.sole.amount
    assert_equal 60_000, invoice.amount_due
  end

  test "a kept credit above a lowered total refunds the difference" do
    invoice = failed_invoice_with_credit 110_000
    invoice.revert_to_draft!
    invoice.update! line_items_attributes: [ { id: invoice.line_items.first.id, unit_price: 80_000 } ]
    invoice.prepare_for_delivery!
    Stripe::PaymentIntent.expects(:create).never
    stub_payment_method "pi_kept", "customer_balance"
    Stripe::Refund.expects(:create)
      .with({ payment_intent: "pi_kept", amount: 22_000, instructions_email: invoice.client.email }, anything)
      .returns(Stripe::Refund.construct_from(id: "pyr_excess"))

    deliver invoice

    assert invoice.paid?
    credit = invoice.payments.credit.sole
    assert_equal [ 88_000, 22_000, "pyr_excess" ], [ credit.amount, credit.excess_amount, credit.stripe_refund_id ]
  end

  test "a bank transfer client's delivery never reads a cash balance" do
    invoice = invoices(:acme_february_draft)
    invoice.prepare_for_delivery!
    Stripe::Customer.expects(:retrieve).never
    Stripe::PaymentIntent.expects(:create).never

    deliver invoice

    assert invoice.sent?
  end

  private

  def preparing_stripe_invoice
    invoices(:acme_february_draft).tap do |invoice|
      invoice.update! client: clients(:sakura)
      invoice.prepare_for_delivery!
    end
  end

  def failed_invoice_with_credit(amount)
    preparing_stripe_invoice.tap do |invoice|
      invoice.payments.create! kind: :credit, amount:, stripe_payment_intent_id: "pi_kept"
      invoice.update! status: :failed, paid_amount: amount
    end
  end

  def stub_cash_balance(*amounts)
    customers = amounts.map { Stripe::Customer.construct_from(id: "cus_test_sakura123", cash_balance: { available: { jpy: it } }) }
    Stripe::Customer.stubs(:retrieve).with(id: "cus_test_sakura123", expand: [ "cash_balance" ]).returns(*customers)
  end

  def stub_checkout_session
    Stripe::Customer.stubs(:retrieve).with("cus_test_sakura123").returns(Stripe::Customer.construct_from(id: "cus_test_sakura123"))
    Stripe::Checkout::Session.stubs(:create).returns(Stripe::Checkout::Session.construct_from(id: "cs_on_delivery"))
  end

  def deliver(invoice)
    CloudflarePdfGateway.stubs(:render).returns("%PDF-fake-content")
    InvoiceMailer.stubs(:send_invoice).returns(stub(deliver_later: true))
    invoice.deliver!
  end

  def checkout_session(**attributes)
    Stripe::Checkout::Session.construct_from(attributes)
  end

  def paid_session(invoice, id: "cs_test", payment_intent: "pi_test", payment_status: "paid", currency: "jpy", amount_total: invoice.total)
    checkout_session(id:, status: "complete", payment_status:, currency:, amount_total:, payment_intent:,
      metadata: { invoice_id: invoice.id.to_s })
  end

  def unpaid_session(invoice, id:, payment_intent: "pi_test")
    checkout_session(id:, status: "complete", payment_status: "unpaid", currency: "jpy", amount_total: invoice.total,
      payment_intent:, metadata: { invoice_id: invoice.id.to_s })
  end

  def payment_intent(status:, id: "pi_test")
    Stripe::PaymentIntent.construct_from(id:, status:)
  end

  def stub_payment_method(payment_intent_id, type)
    Stripe::PaymentIntent.stubs(:retrieve).with(id: payment_intent_id, expand: [ "payment_method" ])
      .returns(Stripe::PaymentIntent.construct_from(id: payment_intent_id, payment_method: { type: }))
  end

  def expired_session(invoice, id:)
    checkout_session(id:, status: "expired", payment_status: "unpaid", metadata: { invoice_id: invoice.id.to_s })
  end
end
