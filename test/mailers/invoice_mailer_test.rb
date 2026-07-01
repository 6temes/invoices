require "test_helper"

class InvoiceMailerTest < ActionMailer::TestCase
  test "send_invoice generates email with correct subject for English locale" do
    invoice = invoices(:sakura_january)
    attach_fake_deliverables invoice

    # Use acme (English locale, bank_transfer) for English subject test
    english_invoice = invoices(:acme_january)
    attach_fake_deliverables english_invoice

    email = InvoiceMailer.send_invoice(english_invoice)

    assert_equal [ "billing@acme.example.com" ], email.to
    expected_subject = "Invoice ##{english_invoice.invoice_number} — Software Development Services"
    assert_equal expected_subject, email.subject
  end

  test "send_invoice generates email with correct subject for Japanese locale" do
    invoice = invoices(:sakura_january)
    attach_fake_deliverables invoice

    email = InvoiceMailer.send_invoice(invoice)

    assert_equal [ "keiri@sakura.example.jp" ], email.to
    expected_subject = "請求書 ##{invoice.invoice_number} — ソフトウェア開発"
    assert_equal expected_subject, email.subject
  end

  test "email includes invoice PDF as attachment" do
    invoice = invoices(:acme_january)
    attach_fake_deliverables invoice

    email = InvoiceMailer.send_invoice(invoice)

    assert_equal 2, email.attachments.size
    pdf_attachment = email.attachments.detect { |a| a.content_type == "application/pdf" }
    assert_not_nil pdf_attachment
    assert_equal "invoice_#{invoice.invoice_number}.pdf", pdf_attachment.filename
  end

  test "email body contains invoice number" do
    invoice = invoices(:acme_january)
    attach_fake_deliverables invoice

    email = InvoiceMailer.send_invoice(invoice)

    assert_match invoice.invoice_number.to_s, email.text_part.body.to_s
    assert_match invoice.invoice_number.to_s, email.html_part.body.to_s
  end

  test "email body contains client greeting for English" do
    invoice = invoices(:acme_january)
    attach_fake_deliverables invoice

    email = InvoiceMailer.send_invoice(invoice)

    assert_match "Hi Acme Corp.,", email.text_part.body.to_s
  end

  test "email body contains client greeting for Japanese" do
    invoice = invoices(:sakura_january)
    attach_fake_deliverables invoice

    email = InvoiceMailer.send_invoice(invoice)

    assert_match "御中", email.text_part.body.to_s
  end

  test "email includes UBL XML as attachment" do
    invoice = invoices(:acme_january)
    attach_fake_deliverables invoice

    email = InvoiceMailer.send_invoice(invoice)

    assert_equal 2, email.attachments.size
    xml_attachment = email.attachments.detect { |a| a.content_type == "application/xml" }
    assert_not_nil xml_attachment
    assert_equal "invoice_#{invoice.invoice_number}.xml", xml_attachment.filename
  end

  test "send_invoice is multipart with html and text parts" do
    invoice = invoices(:acme_january)
    attach_fake_deliverables invoice

    email = InvoiceMailer.send_invoice(invoice)

    assert email.multipart?
    assert email.html_part
    assert email.text_part
  end

  test "send_invoice renders the amount as formatted yen live text" do
    invoice = invoices(:acme_january) # total 110000
    attach_fake_deliverables invoice

    email = InvoiceMailer.send_invoice(invoice)

    assert_includes email.html_part.decoded, "¥110,000"
    assert_includes email.text_part.decoded, "¥110,000"
  end

  test "send_invoice for a credit_card client shows a payment link and no bank details" do
    invoice = invoices(:sakura_january) # ja, credit_card
    attach_fake_deliverables invoice

    email = InvoiceMailer.send_invoice(invoice)

    assert_includes email.html_part.decoded, "/pay/"
    assert_includes email.text_part.decoded, "/pay/"
    assert_not_includes email.html_part.decoded, businesses(:default).bank_account_number
  end

  test "send_invoice for a bank_transfer client shows bank details and no payment link" do
    invoice = invoices(:acme_january) # en, bank_transfer
    attach_fake_deliverables invoice
    business = businesses(:default)

    email = InvoiceMailer.send_invoice(invoice)

    assert_includes email.html_part.decoded, business.bank_name
    assert_includes email.html_part.decoded, business.bank_account_number
    assert_not_includes email.html_part.decoded, "/pay/"
  end

  test "send_invoice localizes the body for Japanese" do
    invoice = invoices(:sakura_january)
    attach_fake_deliverables invoice

    email = InvoiceMailer.send_invoice(invoice)

    assert_includes email.text_part.decoded, "引き続きどうぞよろしくお願いいたします"
  end

  # --- send_reminder ---

  test "send_reminder localizes the subject and body per locale" do
    en = InvoiceMailer.send_reminder(invoices(:acme_january))
    assert_includes en.subject, "Reminder"
    assert_includes en.subject, invoices(:acme_january).invoice_number.to_s
    assert_includes en.text_part.decoded, "Best regards"

    ja = InvoiceMailer.send_reminder(invoices(:sakura_january))
    assert_includes ja.subject, "請求書"
    assert_includes ja.text_part.decoded, "御中"
  end

  test "send_reminder for a credit_card client includes a fresh payment link" do
    email = InvoiceMailer.send_reminder(invoices(:sakura_january)) # ja, credit_card

    assert_includes email.html_part.decoded, "/pay/"
    assert_includes email.text_part.decoded, "/pay/"
  end

  test "send_reminder for a bank_transfer client restates bank details and no link" do
    email = InvoiceMailer.send_reminder(invoices(:acme_january)) # en, bank_transfer

    assert_includes email.html_part.decoded, businesses(:default).bank_name
    assert_not_includes email.html_part.decoded, "/pay/"
  end

  test "send_reminder carries no attachments" do
    email = InvoiceMailer.send_reminder(invoices(:sakura_january))

    assert_empty email.attachments
  end

  test "send_reminder is multipart and shows the amount due and due date as live text" do
    invoice = invoices(:sakura_january) # total 247500, due 2026-02-16

    email = InvoiceMailer.send_reminder(invoice)

    assert email.multipart?
    assert_includes email.html_part.decoded, "¥247,500"
    assert_includes email.html_part.decoded, invoice.due_date.to_s
  end

  # --- send_receipt ---

  test "send_receipt shows the amount paid and paid date as live text (English)" do
    invoice = invoices(:acme_january) # en, paid, paid_amount 110000, paid_on 2026-02-15

    email = InvoiceMailer.send_receipt(invoice)

    assert_includes email.subject, "Payment received"
    assert_includes email.html_part.decoded, "¥110,000"
    assert_includes email.html_part.decoded, invoice.paid_on.to_s
    assert_includes email.text_part.decoded, "Best regards"
  end

  test "send_receipt localizes for Japanese" do
    invoice = invoices(:sakura_january) # ja
    invoice.paid_amount = invoice.total
    invoice.paid_on = Date.new(2026, 2, 20)

    email = InvoiceMailer.send_receipt(invoice)

    assert_includes email.subject, "お支払い確認"
    assert_includes email.html_part.decoded, "御中"
    assert_includes email.html_part.decoded, "¥247,500"
  end

  test "send_receipt is multipart and carries no attachments" do
    email = InvoiceMailer.send_receipt(invoices(:acme_january))

    assert email.multipart?
    assert email.html_part
    assert email.text_part
    assert_empty email.attachments
    assert_not_includes email.html_part.decoded, "/pay/"
  end

  private

  def attach_fake_pdf(invoice)
    invoice.pdf.attach io: StringIO.new("%PDF-1.4 fake"), filename: "invoice.pdf", content_type: "application/pdf"
  end

  def attach_fake_ubl(invoice)
    invoice.ubl_xml.attach io: StringIO.new("<Invoice/>"), filename: "invoice.xml", content_type: "application/xml"
  end

  def attach_fake_deliverables(invoice)
    attach_fake_pdf invoice
    attach_fake_ubl invoice
  end
end
