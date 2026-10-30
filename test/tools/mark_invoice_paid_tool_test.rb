require "test_helper"

class MarkInvoicePaidToolTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  test "marks a sent invoice paid on the given date and emails the receipt" do
    invoice = invoices(:sakura_january)
    attach_deliverables invoice

    assert_enqueued_email_with InvoiceMailer, :send_receipt, args: [ invoice ] do
      response = mark(146, "2026-02-10")
      assert_not response.error?
      assert_equal "paid", JSON.parse(response.content.first[:text])["status"]
    end

    invoice.reload
    assert invoice.paid?
    assert_equal Date.new(2026, 2, 10), invoice.paid_on
    assert_equal invoice.total, invoice.paid_amount
  end

  test "refuses an invoice that is already paid" do
    response = mark(145, "2026-02-10")

    assert response.error?
    assert_match "is paid", response.content.first[:text]
  end

  test "refuses a draft as not found" do
    response = mark(148, "2026-03-10")

    assert response.error?
    assert_match "not found", response.content.first[:text]
    assert invoices(:acme_february_draft).reload.draft?
  end

  test "refuses a payment date before the invoice was issued" do
    attach_deliverables invoices(:sakura_january)
    response = mark(146, "2026-01-15")

    assert response.error?
    assert_match "earlier than the issue date", response.content.first[:text]
    assert invoices(:sakura_january).reload.sent?
  end

  test "refuses a malformed date" do
    response = mark(146, "10/02/2026")

    assert response.error?
    assert invoices(:sakura_january).reload.sent?
  end

  private

  def mark(invoice_number, paid_on)
    MarkInvoicePaidTool.call(invoice_number:, paid_on:, server_context: {})
  end
end
