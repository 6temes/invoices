class InvoiceMailer < ApplicationMailer
  def send_invoice(invoice)
    @invoice = invoice
    @business = Business.instance
    @client = invoice.client

    I18n.with_locale(invoice.locale) do
      @period = @invoice.localized_billing_period
      @payment_url = payment_url_for(invoice) if @client.stripe?
      @credit = invoice.credit_applied
      @preheader = if invoice.amount_due.zero?
        t("invoice_mailer.send_invoice.preheader_paid", number: invoice.invoice_number, period: @period)
      else
        t("invoice_mailer.send_invoice.preheader", number: invoice.invoice_number, period: @period, due_date: invoice.due_date)
      end

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
      @payment_url = payment_url_for(invoice) if @client.stripe?
      @preheader = t("invoice_mailer.send_reminder.preheader",
        number: invoice.invoice_number, due_date: invoice.due_date)

      mail(
        to: @client.email_with_name,
        bcc: @business.email,
        subject: default_i18n_subject(number: invoice.invoice_number, invoice_subject: invoice.subject)
      )
    end
  end

  def send_receipt(invoice)
    @invoice = invoice
    @business = Business.instance
    @client = invoice.client

    I18n.with_locale(invoice.locale) do
      @preheader = t("invoice_mailer.send_receipt.preheader", number: invoice.invoice_number)

      mail(
        to: @client.email_with_name,
        bcc: @business.email,
        subject: default_i18n_subject(number: invoice.invoice_number, invoice_subject: invoice.subject)
      )
    end
  end

  def send_partial_payment(invoice, pending_payment)
    @invoice = invoice
    @business = Business.instance
    @client = invoice.client
    @pending_payment = Invoice::PendingPayment.new(**pending_payment)

    I18n.with_locale(invoice.locale) do
      @preheader = t("invoice_mailer.send_partial_payment.preheader",
        number: invoice.invoice_number, amount_remaining: view_context.yen(@pending_payment.amount_remaining))

      mail(
        to: @client.email_with_name,
        bcc: @business.email,
        subject: default_i18n_subject(number: invoice.invoice_number, invoice_subject: invoice.subject)
      )
    end
  end

  private

  def payment_url_for(invoice)
    token = invoice.signed_id(purpose: :payment, expires_in: Invoice::PAYMENT_LINK_VALIDITY)
    public_payment_url(token:)
  end
end
