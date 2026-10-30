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

  test "treats a draft as not found" do
    response = fetch(148)

    assert response.error?
    assert_match "not found", response.content.first[:text]
  end

  test "treats an unknown number as not found" do
    assert fetch(999).error?
  end

  test "runs a fixed number of queries" do
    assert_queries_count(5) { fetch(145) }
  end

  private

  def fetch(invoice_number)
    GetInvoiceTool.call(invoice_number:, server_context: {})
  end
end
