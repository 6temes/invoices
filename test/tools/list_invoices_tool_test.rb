require "test_helper"

class ListInvoicesToolTest < ActiveSupport::TestCase
  test "lists a year's issued invoices without drafts" do
    template = invoices(:sakura_january).attributes.except("id", "created_at", "updated_at")
    statuses = %w[ sent sent sent paid paid draft ]
    Invoice.insert_all statuses.each_with_index.map { |status, i|
      template.merge "status" => status, "invoice_number" => 900 + i,
        "billing_month" => Date.new(2025, i + 1), "issue_date" => Date.new(2025, i + 1, 5)
    }

    listed = listed_invoices(year: 2025)

    assert_equal 5, listed.size
    assert_not_includes listed.pluck("invoice_number"), 905
  end

  test "returns the fixture year in issue order without the draft" do
    assert_equal [ 145, 146 ], listed_invoices(year: 2026).pluck("invoice_number")
  end

  test "filters by client" do
    assert_equal [ 146 ], listed_invoices(year: 2026, client_id: clients(:sakura).id).pluck("invoice_number")
  end

  test "filters by status" do
    assert_equal [ 145 ], listed_invoices(year: 2026, status: "paid").pluck("invoice_number")
  end

  test "returns nothing for a year without invoices" do
    assert_empty listed_invoices(year: 2019)
  end

  test "carries the booking fields" do
    invoice = listed_invoices(year: 2026).first

    assert_equal "Acme Corp.", invoice["client"]["name"]
    assert_equal "2026-02-01", invoice["issue_date"]
    assert_equal 110000, invoice["total"]
    assert_equal "2026-02-15", invoice["paid_on"]
  end

  test "runs a fixed number of queries" do
    assert_queries_count(2) { listed_invoices(year: 2026) }
  end

  private

  def listed_invoices(**arguments)
    response = ListInvoicesTool.call(**arguments, server_context: {})
    JSON.parse(response.content.first[:text])["invoices"]
  end
end
