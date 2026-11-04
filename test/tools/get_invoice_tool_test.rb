require "test_helper"

class GetInvoiceToolTest < ActiveSupport::TestCase
  test "reports missing files for an invoice still preparing" do
    invoices(:sakura_january).update_column :status, "preparing"
    CloudflarePdfGateway.expects(:render).never

    response = fetch(146)

    assert_not response.error?
    assert_equal 1, response.content.size
    files = JSON.parse(response.content.first[:text])["files"]
    assert_equal false, files["pdf"]["attached"]
    assert_equal false, files["ubl_xml"]["attached"]
  end

  test "embeds the attached PDF and UBL" do
    invoice = invoices(:sakura_january)
    invoice.pdf.attach io: StringIO.new("%PDF-1.4 sakura"), filename: "invoice_146.pdf", content_type: "application/pdf"
    invoice.ubl_xml.attach io: StringIO.new("<Invoice/>"), filename: "invoice_146.xml", content_type: "application/xml"

    pdf, xml = fetch(146).content.drop(1)

    assert_equal "resource", pdf[:type]
    assert_equal "application/pdf", pdf[:resource][:mimeType]
    assert pdf[:resource][:uri].end_with?("invoice_146.pdf")
    assert_equal "%PDF-1.4 sakura", Base64.strict_decode64(pdf[:resource][:blob])
    assert_equal "application/xml", xml[:resource][:mimeType]
    assert_equal "<Invoice/>", Base64.strict_decode64(xml[:resource][:blob])
  end

  test "carries every booking field and the line items" do
    data = JSON.parse(fetch(145).content.first[:text])

    assert_equal 145, data["invoice_number"]
    assert_equal "Acme Corp.", data["client"]["name"]
    assert_equal "T1234567890123", data["client"]["tax_registration_number"]
    assert_equal "2026-03-03", data["due_date"]
    assert_equal 10000, data["tax_amount"]
    assert_equal "2026-02-15", data["paid_on"]
    assert_equal 110000, data["paid_amount"]
    assert_equal [ 100000 ], data["line_items"].pluck("amount")
  end

  test "lists the payments behind the paid amount" do
    payments = JSON.parse(fetch(145).content.first[:text])["payments"]

    assert_equal [ {
      "kind" => "manual", "status" => "succeeded", "amount" => 110000,
      "excess_amount" => 0, "refund_status" => nil, "paid_on" => "2026-02-15"
    } ], payments
  end

  test "orders payments by date and shows whether excess was refunded" do
    invoice = invoices(:sakura_january)
    invoice.payments.create! kind: :checkout, amount: 100_000, excess_amount: 5_000, paid_on: Date.new(2026, 2, 20),
      stripe_payment_intent_id: "pi_test_late", stripe_refund_id: "re_test_late"
    invoice.payments.create! kind: :checkout, amount: 100_000, excess_amount: 3_000, paid_on: Date.new(2026, 2, 10),
      stripe_payment_intent_id: "pi_test_early"

    payments = JSON.parse(fetch(146).content.first[:text])["payments"]

    assert_equal [ "2026-02-10", "2026-02-20" ], payments.pluck("paid_on")
    assert_equal [ "awaiting", "issued" ], payments.pluck("refund_status")
    assert_equal [ 3_000, 5_000 ], payments.pluck("excess_amount")
    assert_empty payments.flat_map(&:keys).grep(/stripe|\Aid\z|idempotency/)
  end

  test "lists no payments for an unpaid invoice" do
    assert_equal [], JSON.parse(fetch(146).content.first[:text])["payments"]
  end

  test "treats a draft as not found" do
    response = fetch(148)

    assert response.error?
    assert_match "not found", response.content.first[:text]
  end

  test "treats an unknown number as not found" do
    assert fetch(999).error?
  end

  test "runs a fixed number of queries however many payments there are" do
    invoices(:acme_january).payments.create! kind: :manual, amount: 0, excess_amount: 1_000
    assert_queries_count(6) { fetch(145) }
  end

  private

  def fetch(invoice_number)
    GetInvoiceTool.call(invoice_number:, server_context: {})
  end
end
