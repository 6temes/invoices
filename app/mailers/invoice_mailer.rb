class InvoiceMailer < ApplicationMailer
  def send_invoice(invoice)
    @invoice = invoice
    @business = Business.instance
    @client = invoice.client

    I18n.with_locale(invoice.locale) do
      @period = @invoice.localized_billing_period
      @payment_url = payment_url_for(invoice) if @client.credit_card?
      @preheader = t("invoice_mailer.send_invoice.preheader",
        number: invoice.invoice_number, period: @period, due_date: invoice.due_date)

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
        subject: default_i18n_subject(number: invoice.invoice_number, invoice_subject: invoice.subject)
      )
    end
  end

  def send_reminder(invoice)
    @invoice = invoice
    @business = Business.instance
    @client = invoice.client

    I18n.with_locale(invoice.locale) do
      @period = @invoice.localized_billing_period
      @payment_url = payment_url_for(invoice) if @client.credit_card?
      @preheader = t("invoice_mailer.send_reminder.preheader",
        number: invoice.invoice_number, due_date: invoice.due_date)

      mail(
        to: @client.email_with_name,
        bcc: @business.email,
        subject: default_i18n_subject(number: invoice.invoice_number, invoice_subject: invoice.subject)
      )
    end
  end

  private

  def payment_url_for(invoice)
    token = invoice.signed_id(purpose: :payment, expires_in: 60.days)
    public_payment_url(token:)
  end
end
