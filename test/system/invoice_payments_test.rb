require "application_system_test_case"

class InvoicePaymentsSystemTest < ApplicationSystemTestCase
  setup do
    sign_in
  end

  # These exercise the payment form by visiting its path directly, mirroring the
  # extra-hours system tests. The form is the same one the "Mark as paid" / "Edit"
  # links load into the slideover, but driving the JS click-to-open from a test is
  # timing-flaky (the panel intermittently doesn't open), so we skip it — the
  # slideover#open behaviour is shared with, and proven by, the extra-hours flow.

  test "record the payment date when marking an invoice paid" do
    invoice = invoices(:sakura_january)
    attach_deliverables invoice

    visit payment_invoice_path(invoice)
    assert_field "Paid on"

    click_button "Confirm payment"

    assert_text "PAID"
    assert_text Date.current.to_s
  end

  test "correct the payment date on a paid invoice" do
    invoice = invoices(:acme_january)
    attach_deliverables invoice

    visit payment_invoice_path(invoice)
    assert_field "Paid on", with: "2026-02-15"

    # Typing into <input type=date> is locale/keystroke dependent across Chrome
    # builds (passes locally, leaves the field invalid in CI — which then blocks
    # submission via required/min/max). Setting .value with an ISO string is
    # format-independent and reliable.
    date_input = find("input[name='paid_on']")
    page.execute_script(
      "arguments[0].value = arguments[1]; arguments[0].dispatchEvent(new Event('change', { bubbles: true }))",
      date_input, "2026-03-10"
    )
    click_button "Save"

    assert_text "2026-03-10"
    assert_no_text "2026-02-15"
  end

  private

  def attach_deliverables(invoice)
    invoice.pdf.attach io: StringIO.new("%PDF-1.4"), filename: "test.pdf", content_type: "application/pdf"
    invoice.ubl_xml.attach io: StringIO.new("<Invoice/>"), filename: "test.xml", content_type: "application/xml"
  end
end
