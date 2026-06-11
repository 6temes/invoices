require "test_helper"

class InvoiceDeliveryJobTest < ActiveSupport::TestCase
  test "delivers the invoice" do
    invoice = invoices(:acme_february_draft)
    invoice.prepare_for_delivery!
    invoice.expects(:deliver!).once

    InvoiceDeliveryJob.new.perform invoice
  end

  test "permanent failure via discard_on marks invoice as failed" do
    invoice = invoices(:acme_february_draft)
    invoice.prepare_for_delivery!

    CloudflarePdfGateway.stubs(:render).raises(CloudflarePdfGateway::ClientError.new("bad request"))

    InvoiceDeliveryJob.perform_now invoice

    assert invoice.reload.failed?
  end

  test "Stripe authentication failure marks invoice as failed" do
    invoice = invoices(:acme_february_draft)
    invoice.prepare_for_delivery!

    Invoice.any_instance.stubs(:deliver!).raises(Stripe::AuthenticationError.new("invalid key"))

    InvoiceDeliveryJob.perform_now invoice

    assert invoice.reload.failed?
  end

  test "UBL builder error marks invoice as failed" do
    invoice = invoices(:acme_february_draft)
    invoice.prepare_for_delivery!

    Invoice.any_instance.stubs(:deliver!).raises(UblInvoiceBuilder::Error.new("missing data"))

    InvoiceDeliveryJob.perform_now invoice

    assert invoice.reload.failed?
  end

  test "InvalidStatusError discard does not mark invoice as failed" do
    invoice = invoices(:sakura_january)

    InvoiceDeliveryJob.perform_now invoice

    assert invoice.reload.sent?
  end

  test "retry exhaustion marks invoice as failed" do
    invoice = invoices(:acme_february_draft)
    invoice.prepare_for_delivery!

    error = CloudflarePdfGateway::ServerError.new("server error")

    job = InvoiceDeliveryJob.new(invoice)
    job.send :mark_invoice_failed, invoice, error

    assert invoice.reload.failed?
  end

  test "reports error to Rails error reporter on failure" do
    invoice = invoices(:acme_february_draft)
    invoice.prepare_for_delivery!

    error = CloudflarePdfGateway::ClientError.new("bad request")
    Rails.error.expects(:report).with(error, context: { invoice_id: invoice.id })

    job = InvoiceDeliveryJob.new(invoice)
    job.send :mark_invoice_failed, invoice, error
  end
end
