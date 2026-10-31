module Invoice::Deliverable
  extend ActiveSupport::Concern

  def prepare_for_delivery!
    raise Invoice::InvalidStatusError, "Invoice must be in draft status to prepare for delivery" unless draft?

    update! status: :preparing
  end

  def mark_as_failed!
    raise Invoice::InvalidStatusError, "Invoice must be in preparing status to mark as failed" unless preparing?

    update! status: :failed
  end

  def retry_delivery!
    raise Invoice::InvalidStatusError, "Invoice must be in failed status to retry delivery" unless failed?

    update! status: :preparing, stripe_checkout_session_id: nil
  end

  def revert_to_draft!
    raise Invoice::InvalidStatusError, "Invoice must be in failed status to revert to draft" unless failed?

    update! status: :draft, stripe_checkout_session_id: nil
  end

  def deliver!
    raise Invoice::InvalidStatusError, "Invoice must be in preparing status to deliver" unless preparing?

    create_checkout_session! if client.credit_card? && stripe_checkout_session_id.blank?

    html = render_standalone_html
    pdf_binary = CloudflarePdfGateway.render html
    xml_string = UblInvoiceBuilder.new(self).to_xml

    transaction do
      pdf.attach io: StringIO.new(pdf_binary), filename: pdf_filename, content_type: "application/pdf"
      ubl_xml.attach io: StringIO.new(xml_string), filename: ubl_filename, content_type: "application/xml"
      update! status: :sent, sent_at: Time.current
    end

    InvoiceMailer.send_invoice(self).deliver_later
  end

  private

  def render_standalone_html
    ApplicationController.renderer.new(
      "HTTP_HOST" => default_host
    ).render(
      partial: "invoices/pdf_template",
      locals: { invoice: self, business: Business.instance },
      formats: [ :html ]
    )
  end

  def pdf_filename
    "invoice_#{invoice_number}.pdf"
  end

  def ubl_filename
    "invoice_#{invoice_number}.xml"
  end
end
