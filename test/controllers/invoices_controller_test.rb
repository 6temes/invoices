require "test_helper"

class InvoicesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:daniel)
  end

  test "index renders dashboard" do
    get invoices_path
    assert_response :success
  end

  test "index filters by client" do
    get invoices_path(client_id: clients(:acme).id)
    assert_response :success
  end

  test "index filters by status" do
    get invoices_path(status: "draft")
    assert_response :success
  end

  test "show displays invoice" do
    get invoice_path(invoices(:acme_february_draft))
    assert_response :success
  end

  test "show displays client registration number when present" do
    invoice = invoices(:acme_february_draft)
    invoice.client.update! tax_registration_number: "T1234567890123"

    get invoice_path(invoice)

    assert_response :success
    assert_includes response.body, "JP TRN T1234567890123"
  end

  test "show omits client registration number when blank" do
    invoice = invoices(:acme_february_draft)
    invoice.client.update! tax_registration_number: nil

    get invoice_path(invoice)

    assert_response :success
    assert_select ".detail-value" do |values|
      client_block = values.detect { |value| value.text.include? invoice.client.name }
      assert_not_includes client_block.text, "JP TRN"
    end
  end

  test "new renders form" do
    get new_invoice_path
    assert_response :success
  end

  test "new with client_id pre-fills from retainer" do
    get new_invoice_path(client_id: clients(:fuji).id)
    assert_response :success
  end

  test "new redirects to existing invoice for same client and billing month" do
    travel_to Date.new(2026, 3, 1) do
      get new_invoice_path(client_id: clients(:acme).id)
      assert_redirected_to invoice_path(invoices(:acme_february_draft))
    end
  end

  test "create saves invoice and increments invoice number" do
    business = businesses(:default)
    starting_number = business.next_invoice_number

    assert_difference "Invoice.count" do
      post invoices_path, params: {
        invoice: {
          client_id: clients(:fuji).id,
          locale: "en",
          billing_month: "2026-01-01",
          issue_date: "2026-03-01",
          due_date: "2026-03-31",
          tax_rate: 10,
          line_items_attributes: {
            "0" => {
              item_type: "Service",
              description: "Test service",
              quantity: 1,
              unit_price: 50000
            }
          }
        }
      }
    end

    assert_redirected_to invoice_path(Invoice.last)
    assert_equal starting_number + 1, business.reload.next_invoice_number
  end

  test "edit renders form for draft invoice" do
    get edit_invoice_path(invoices(:acme_february_draft))
    assert_response :success
  end

  test "update changes draft invoice" do
    patch invoice_path(invoices(:acme_february_draft)), params: {
      invoice: { notes: "Updated notes" }
    }
    assert_redirected_to invoice_path(invoices(:acme_february_draft))
    assert_equal "Updated notes", invoices(:acme_february_draft).reload.notes
  end

  test "destroy deletes draft invoice" do
    assert_difference "Invoice.count", -1 do
      delete invoice_path(invoices(:acme_february_draft))
    end
    assert_redirected_to invoices_path
  end

  test "destroy rejects non-draft invoice" do
    assert_no_difference "Invoice.count" do
      delete invoice_path(invoices(:acme_january))
    end
    assert_redirected_to invoice_path(invoices(:acme_january))
  end

  test "deliver transitions draft invoice to preparing and enqueues job" do
    invoice = invoices(:acme_february_draft)
    assert_enqueued_with(job: InvoiceDeliveryJob) do
      post deliver_invoice_path(invoice)
    end
    assert_redirected_to invoices_path
    assert invoice.reload.preparing?
  end

  test "deliver redirects with alert for non-draft invoice" do
    invoice = invoices(:sakura_january)
    post deliver_invoice_path(invoice)
    assert_redirected_to invoice_path(invoice)
    assert_equal "Only draft invoices can be sent.", flash[:alert]
  end

  test "retry_delivery transitions failed invoice to preparing and enqueues job" do
    invoice = invoices(:acme_february_draft)
    invoice.prepare_for_delivery!
    invoice.mark_as_failed!

    assert_enqueued_with(job: InvoiceDeliveryJob) do
      post retry_delivery_invoice_path(invoice)
    end
    assert_redirected_to invoice_path(invoice)
    assert invoice.reload.preparing?
  end

  test "retry_delivery redirects with alert for non-failed invoice" do
    invoice = invoices(:acme_february_draft)
    post retry_delivery_invoice_path(invoice)
    assert_redirected_to invoice_path(invoice)
    assert_equal "Only failed invoices can be retried.", flash[:alert]
  end

  test "revert_to_draft transitions failed invoice to draft" do
    invoice = invoices(:acme_february_draft)
    invoice.prepare_for_delivery!
    invoice.mark_as_failed!

    post revert_to_draft_invoice_path(invoice)
    assert_redirected_to invoice_path(invoice)
    assert invoice.reload.draft?
  end

  test "revert_to_draft redirects with alert for non-failed invoice" do
    invoice = invoices(:acme_february_draft)
    post revert_to_draft_invoice_path(invoice)
    assert_redirected_to invoice_path(invoice)
    assert_equal "Only failed invoices can be reverted to draft.", flash[:alert]
  end

  test "edit redirects for preparing invoice" do
    invoice = invoices(:acme_february_draft)
    invoice.prepare_for_delivery!

    get edit_invoice_path(invoice)
    assert_redirected_to invoice_path(invoice)
    assert_equal "Only draft invoices can be edited.", flash[:alert]
  end

  test "edit redirects for failed invoice" do
    invoice = invoices(:acme_february_draft)
    invoice.prepare_for_delivery!
    invoice.mark_as_failed!

    get edit_invoice_path(invoice)
    assert_redirected_to invoice_path(invoice)
  end

  test "mark_as_paid transitions sent invoice" do
    invoice = invoices(:sakura_january)
    invoice.pdf.attach io: StringIO.new("%PDF-1.4"), filename: "test.pdf", content_type: "application/pdf"
    invoice.ubl_xml.attach io: StringIO.new("<Invoice/>"), filename: "test.xml", content_type: "application/xml"

    post mark_as_paid_invoice_path(invoice)
    assert_redirected_to invoice_path(invoice)
    assert invoice.reload.paid?
  end

  test "mark_as_paid records the submitted payment date" do
    invoice = invoices(:sakura_january)
    attach_deliverables invoice

    post mark_as_paid_invoice_path(invoice), params: { paid_on: "2026-05-03" }

    assert_redirected_to invoice_path(invoice)
    assert_equal Date.new(2026, 5, 3), invoice.reload.paid_on
  end

  test "payment renders the slideover form for a sent invoice" do
    get payment_invoice_path(invoices(:sakura_january))
    assert_response :success
  end

  test "payment renders the slideover form for a paid invoice" do
    get payment_invoice_path(invoices(:acme_january))
    assert_response :success
  end

  test "payment redirects for a draft invoice" do
    invoice = invoices(:acme_february_draft)
    get payment_invoice_path(invoice)
    assert_redirected_to invoice_path(invoice)
  end

  test "update_payment corrects the payment date on a paid invoice" do
    invoice = invoices(:acme_january)
    attach_deliverables invoice

    patch update_payment_invoice_path(invoice), params: { paid_on: "2026-03-10" }

    assert_redirected_to invoice_path(invoice)
    assert_equal Date.new(2026, 3, 10), invoice.reload.paid_on
  end

  test "update_payment rejects a non-paid invoice" do
    invoice = invoices(:sakura_january)

    patch update_payment_invoice_path(invoice), params: { paid_on: "2026-03-10" }

    assert_redirected_to invoice_path(invoice)
    assert_nil invoice.reload.paid_on
  end

  test "update_payment rejects an out-of-range payment date without persisting it" do
    invoice = invoices(:acme_january)
    attach_deliverables invoice
    original = invoice.paid_on

    patch update_payment_invoice_path(invoice), params: { paid_on: (Date.current + 30).to_s }

    assert_response :unprocessable_entity
    assert_equal original, invoice.reload.paid_on
  end

  test "create with invalid data does not increment invoice number" do
    business = businesses(:default)
    original_number = business.next_invoice_number

    post invoices_path, params: { invoice: {
      client_id: clients(:acme).id,
      locale: "en",
      billing_month: "2026-03-01",
      issue_date: "",
      due_date: "",
      tax_rate: 10.0
    } }

    assert_response :unprocessable_entity
    assert_equal original_number, business.reload.next_invoice_number
  end

  test "create handles duplicate client billing month gracefully" do
    assert_no_difference "Invoice.count" do
      post invoices_path, params: {
        invoice: {
          client_id: clients(:acme).id,
          locale: "en",
          billing_month: "2026-01-01",
          issue_date: "2026-03-01",
          due_date: "2026-03-31",
          tax_rate: 10,
          line_items_attributes: {
            "0" => {
              item_type: "Service",
              description: "Test",
              quantity: 1,
              unit_price: 50000
            }
          }
        }
      }
    end

    assert_response :unprocessable_entity
  end

  test "requires authentication" do
    sign_out
    get invoices_path
    assert_redirected_to new_session_path
  end

  private

  def attach_deliverables(invoice)
    invoice.pdf.attach io: StringIO.new("%PDF-1.4"), filename: "test.pdf", content_type: "application/pdf"
    invoice.ubl_xml.attach io: StringIO.new("<Invoice/>"), filename: "test.xml", content_type: "application/xml"
  end
end
