class InvoiceMailer < ApplicationMailer
  def send_invoice(invoice)
    @invoice = invoice
    @business = Business.instance
    @client = invoice.client

    I18n.with_locale(invoice.locale) do
      @subject_line = t("invoice_mailer.send_invoice.subject",
        number: invoice.invoice_number,
        invoice_subject: invoice.subject)

      @period = @invoice.localized_billing_period
      @payment_url = payment_url_for(invoice) if @client.credit_card?

      attachments["invoice_#{invoice.invoice_number}.pdf"] = {
        mime_type: "application/pdf",
        content: invoice.pdf.download
      }

      if invoice.ubl_xml.attached?
        attachments["invoice_#{invoice.invoice_number}.xml"] = {
          mime_type: "application/xml",
          content: invoice.ubl_xml.download
        }
      end

      mail(
        to: @client.email_with_name,
        bcc: @business.email,
        subject: @subject_line
      )
    end
  end

  private

  def payment_url_for(invoice)
    token = invoice.signed_id(purpose: :payment, expires_in: 60.days)
    public_payment_url(token:)
  end
end
