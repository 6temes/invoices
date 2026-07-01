# Preview all emails at http://localhost:3000/rails/mailers/invoice_mailer
#
# QA surface for the email redesign: renders each of the three emails in both
# locales (EN via a bank-transfer client, JA via a credit-card client) against
# real development data. Pair with letter_opener for full-delivery checks.
class InvoiceMailerPreview < ActionMailer::Preview
  # http://localhost:3000/rails/mailers/invoice_mailer/send_invoice_en
  def send_invoice_en
    InvoiceMailer.send_invoice(deliverable_invoice("en"))
  end

  def send_invoice_ja
    InvoiceMailer.send_invoice(deliverable_invoice("ja"))
  end

  def send_reminder_en
    InvoiceMailer.send_reminder(invoice("en"))
  end

  def send_reminder_ja
    InvoiceMailer.send_reminder(invoice("ja"))
  end

  def send_receipt_en
    InvoiceMailer.send_receipt(paid_invoice("en"))
  end

  def send_receipt_ja
    InvoiceMailer.send_receipt(paid_invoice("ja"))
  end

  private

  def invoice(locale)
    Invoice.where(locale:).order(id: :desc).first || Invoice.first
  end

  # send_invoice downloads the attached PDF, so pick a finalized invoice that
  # has one (attaching to a draft is rejected by the invoice's own validations).
  def deliverable_invoice(locale)
    finalized = Invoice.where(locale:, status: %w[sent paid])
    with_sample_pdf(finalized.detect { it.pdf.attached? } || finalized.first || invoice(locale))
  end

  def paid_invoice(locale)
    sample = Invoice.where(locale:, status: "paid").first || invoice(locale)
    sample.paid_amount = sample.total if sample.paid_amount.to_i.zero?
    sample.paid_on ||= Date.current
    sample
  end

  def with_sample_pdf(sample)
    if !sample.pdf.attached? && !sample.draft?
      sample.pdf.attach io: StringIO.new("%PDF-1.4 sample invoice"),
        filename: "invoice.pdf", content_type: "application/pdf"
    end
    sample
  end
end
