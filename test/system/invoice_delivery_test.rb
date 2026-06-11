require "application_system_test_case"

class InvoiceDeliverySystemTest < ApplicationSystemTestCase
  setup do
    sign_in
    @invoice = invoices(:acme_february_draft)
  end

  test "send invoice button has turbo submits with attribute" do
    visit invoice_path(@invoice)
    send_button = find("input[value='Send invoice'], button", text: "Send invoice")
    assert_equal "Sending...", send_button[:"data-turbo-submits-with"]
  end

  test "delivering invoice transitions to preparing and enqueues job" do
    visit invoice_path(@invoice)

    accept_confirm do
      click_on "Send invoice"
    end

    assert_text "Invoice is being sent..."
    assert @invoice.reload.preparing?
  end

  test "preparing invoice shows sending state with no action buttons" do
    @invoice.prepare_for_delivery!
    visit invoice_path(@invoice)

    assert_selector ".badge-preparing", text: "PREPARING"
    assert_text "Sending..."
    assert_no_button "Send invoice"
    assert_no_button "Edit"
    assert_no_button "Delete"
  end

  test "failed invoice shows retry and revert buttons" do
    @invoice.prepare_for_delivery!
    @invoice.mark_as_failed!
    visit invoice_path(@invoice)

    assert_selector ".badge-failed", text: "FAILED"
    assert_button "Retry"
    assert_button "Revert to draft"
    assert_no_button "Send invoice"
  end

  test "retrying failed invoice transitions back to preparing" do
    @invoice.prepare_for_delivery!
    @invoice.mark_as_failed!
    visit invoice_path(@invoice)

    accept_confirm do
      click_on "Retry"
    end

    assert_text "Retrying invoice delivery..."
    assert @invoice.reload.preparing?
  end

  test "reverting failed invoice to draft makes it editable" do
    @invoice.prepare_for_delivery!
    @invoice.mark_as_failed!
    visit invoice_path(@invoice)

    accept_confirm do
      click_on "Revert to draft"
    end

    assert_text "Invoice reverted to draft."
    assert @invoice.reload.draft?

    visit invoice_path(@invoice)
    assert_selector ".badge-draft", text: "DRAFT"
    assert_link "Edit"
    assert_button "Send invoice"
  end

  test "editing preparing invoice redirects with alert" do
    @invoice.prepare_for_delivery!
    visit edit_invoice_path(@invoice)

    assert_text "Only draft invoices can be edited."
    assert_current_path invoice_path(@invoice)
  end

  test "editing failed invoice redirects with alert" do
    @invoice.prepare_for_delivery!
    @invoice.mark_as_failed!
    visit edit_invoice_path(@invoice)

    assert_text "Only draft invoices can be edited."
    assert_current_path invoice_path(@invoice)
  end
end
