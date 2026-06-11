require "application_system_test_case"

class InvoicesSystemTest < ApplicationSystemTestCase
  setup do
    sign_in
  end

  test "index page renders summary cards and chart" do
    visit invoices_path
    assert_selector ".summary-card"
    assert_selector "[data-controller='chart']", visible: :all
    assert_link "New invoice"
  end

  test "chart survives a real morph refresh" do
    visit invoices_path
    assert_selector ".chart-bar"

    # Tag the current bars, then trigger a real same-URL Turbo visit, which is
    # a refresh → morph. The morph wipes our JS-rendered bars; the fix re-renders
    # fresh (untagged) ones. Asserting on :not([data-pre-morph]) can't pass on the
    # pre-morph DOM, so it only succeeds once the chart has actually re-rendered.
    page.execute_script(<<~JS)
      document.querySelectorAll(".chart-bar").forEach(b => b.dataset.preMorph = "1")
      Turbo.visit(window.location.href, { action: "replace" })
    JS

    assert_selector ".chart-bar:not([data-pre-morph])"
  end

  test "index tab switching between open and all" do
    visit invoices_path
    assert_link "Open"
    assert_link "All"
    click_on "All"
    assert_current_path(/tab=all/)
  end

  test "index year filter dropdown" do
    visit invoices_path
    assert_selector "select[name=year]"
  end

  test "index client filter dropdown" do
    visit invoices_path
    assert_selector "select[name=client_id]"
  end

  test "new invoice form renders all fields" do
    visit new_invoice_path
    assert_selector "select[name='invoice[client_id]']"
    assert_selector "select[name='invoice[locale]']"
    assert_field "invoice[billing_month]"
    assert_field "invoice[issue_date]"
    assert_field "invoice[due_date]"
    assert_field "invoice[tax_rate]"
    assert_text "Line Items"
    assert_button "+ Add line item"
  end

  test "new invoice line items section present" do
    visit new_invoice_path
    assert_text "Line Items"
    assert_selector "[data-controller='line-items']"
    assert_selector "[data-action='line-items#add']"
    assert_selector "template[data-line-items-target='template']", visible: false
  end

  test "index handles invalid status filter gracefully" do
    visit invoices_path(status: "bogus")
    assert_text "Invoices"
  end

  test "add line item button inserts fields via Stimulus" do
    visit new_invoice_path

    assert_no_selector "[data-line-items-target='container'] .card"
    click_on "+ Add line item"
    assert_selector "[data-line-items-target='container'] .card"
    assert_selector "input[name*='line_items_attributes'][name*='description']"
  end

  test "create invoice with line items" do
    visit new_invoice_path

    select clients(:fuji).name, from: "invoice[client_id]"

    click_on "+ Add line item"
    assert_selector "[data-line-items-target='container'] .card"

    within "[data-line-items-target='container']" do
      find("input[name*='description']").fill_in with: "Development work"
      find("input[name*='quantity']").fill_in with: "10"
      find("input[name*='unit_price']").fill_in with: "15000"
    end

    click_button "Save"

    assert_text "Invoice created"
    assert_text "Software Development Services"
    assert_text "Development work"
    assert_text "150,000"
  end

  test "invoice detail page shows all sections" do
    visit invoice_path(invoices(:acme_february_draft))

    assert_text "Invoice ##{invoices(:acme_february_draft).invoice_number}"
    assert_text "DRAFT"
    assert_text invoices(:acme_february_draft).client.name
    assert_text "Subtotal"
    assert_text "Tax"
    assert_text "Total"
    assert_link "Edit"
    assert_button "Send invoice"
    assert_button "Delete"
  end
end
