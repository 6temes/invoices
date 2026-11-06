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
    expected_subject = "Invoice ##{english_invoice.invoice_number}: Software Development Services"
    assert_equal expected_subject, email.subject
  end

  test "send_invoice generates email with correct subject for Japanese locale" do
    invoice = invoices(:sakura_january)
    attach_fake_deliverables invoice

    email = InvoiceMailer.send_invoice(invoice)

    assert_equal [ "keiri@sakura.example.jp" ], email.to
    expected_subject = "請求書 ##{invoice.invoice_number}：ソフトウェア開発"
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
    invoice.update_columns status: "sent", paid_amount: 0, paid_on: nil
    attach_fake_deliverables invoice

    email = InvoiceMailer.send_invoice(invoice)

    assert_includes email.html_part.decoded, "¥110,000"
    assert_includes email.text_part.decoded, "¥110,000"
  end

  test "send_invoice for a stripe client shows a payment link and no bank details" do
    invoice = invoices(:sakura_january) # ja, stripe
    attach_fake_deliverables invoice

    email = InvoiceMailer.send_invoice(invoice)

    assert_includes email.html_part.decoded, "/pay/"
    assert_includes email.text_part.decoded, "/pay/"
    # Assert on the bank name, not the account number: a short numeric string can
    # collide with the random signed-id token in the payment URL.
    assert_not_includes email.html_part.decoded, businesses(:default).bank_name
  end

  test "send_invoice for a bank_transfer client shows bank details and no payment link" do
    invoice = invoices(:acme_january) # en, bank_transfer
    invoice.update_columns status: "sent", paid_amount: 0
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

  # --- send_partial_payment ---

  test "send_partial_payment tells the client what arrived, what is still due and where to send it" do
    invoice = invoices(:sakura_january) # ja, stripe

    email = InvoiceMailer.send_partial_payment(invoice, partial_payment(received: 247_060, remaining: 440))

    assert_includes email.subject, invoice.invoice_number.to_s
    [ email.html_part.decoded, email.text_part.decoded ].each do |body|
      assert_includes body, "¥440"
      assert_includes body, "¥247,060"
      assert_includes body, "¥247,500"
      assert_includes body, "Example Bank"
      assert_includes body, "7654321"
      assert_includes body, "普通"
      assert_includes body, "https://payments.stripe.com/bank_transfers/instructions/test_example"
      assert_includes body, "/pay/"
      assert_not_includes body, businesses(:default).bank_name
    end
    assert_empty email.attachments
  end

  test "send_partial_payment speaks the client's language" do
    invoice = invoices(:sakura_january)
    invoice.update_columns locale: "en"

    email = InvoiceMailer.send_partial_payment(invoice, partial_payment(received: 100_000, remaining: 147_500))

    assert_includes email.subject, "Partial payment"
    assert_includes email.text_part.decoded, "I've received ¥100,000"
    assert_includes email.text_part.decoded, "Ordinary"
  end

  test "send_partial_payment after credit was applied shows the figures and leaves out the bank details" do
    invoice = invoices(:sakura_january)
    invoice.update_columns locale: "en", paid_amount: 117_500

    email = InvoiceMailer.send_partial_payment(invoice, { amount_received: 20_000, amount_remaining: 130_000 })

    assert_includes email.text_part.decoded, "I've applied ¥20,000 of your credit"
    [ email.html_part.decoded, email.text_part.decoded ].each do |body|
      assert_includes body, "Credit applied"
      assert_not_includes body, "Received so far"
      assert_includes body, "¥150,000"
      assert_includes body, "¥130,000"
      assert_includes body, "/pay/"
      assert_not_includes body, "Please transfer the rest"
      assert_not_includes body, "transfer instructions"
    end
  end

  # --- send_credit_notice ---

  test "send_credit_notice offers the return link when the credit covers the fee" do
    client = clients(:sakura)
    client.update! credit_notified_amount: 10_000

    email = InvoiceMailer.send_credit_notice(client, 10_000)
    token = email.text_part.decoded[%r{/credit/(\S+)}, 1]

    assert_equal client, Client.find_by_token_for(:credit_refund, token)
    assert_equal [ client.email ], email.to
    assert_includes email.subject, "¥10,000"
    [ email.html_part.decoded, email.text_part.decoded ].each do |body|
      assert_includes body, "御中"
      assert_includes body, "75日"
      assert_includes body, "¥275"
      assert_match %r{/credit/[^"\s]+}, body
    end
  end

  test "send_credit_notice leaves out the return link when the credit is too small to return" do
    client = clients(:sakura)
    client.update! locale: "en", credit_notified_amount: 549

    email = InvoiceMailer.send_credit_notice(client, 549)

    assert_includes email.text_part.decoded, "I'm holding ¥549 of your payments as credit"
    [ email.html_part.decoded, email.text_part.decoded ].each do |body|
      assert_not_includes body, "/credit/"
      assert_not_includes body, "returned now"
    end
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

  test "send_reminder for a stripe client includes a fresh payment link" do
    email = InvoiceMailer.send_reminder(invoices(:sakura_january)) # ja, stripe

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

  test "send_invoice and send_reminder ask only for what is still due, in both locales" do
    { invoices(:acme_january) => "¥10,000", invoices(:sakura_january) => "¥147,500" }.each do |invoice, remaining|
      invoice.update_columns status: "sent", paid_amount: invoice.total - remaining.delete("¥,").to_i

      [ InvoiceMailer.send_invoice(invoice), InvoiceMailer.send_reminder(invoice) ].each do |email|
        assert_includes email.html_part.decoded, remaining, invoice.locale
        assert_includes email.text_part.decoded, remaining, invoice.locale
      end
    end
  end

  test "send_invoice shows the credit applied and asks only for the rest" do
    invoice = invoices(:sakura_january) # ja, stripe, total 247,500
    invoice.payments.create! kind: :credit, amount: 47_500, stripe_payment_intent_id: "pi_credit"
    invoice.update_columns paid_amount: 47_500
    attach_fake_deliverables invoice

    { "ja" => "充当", "en" => "¥47,500 of your credit; ¥200,000 is due." }.each do |locale, credit_line|
      invoice.update_columns locale: locale
      email = InvoiceMailer.send_invoice(invoice)

      [ email.html_part.decoded, email.text_part.decoded ].each do |body|
        assert_includes body, credit_line, locale
        assert_includes body, "¥247,500", locale
        assert_includes body, "/pay/", locale
        assert_includes body, invoice.due_date.to_s, locale
      end
    end
  end

  test "send_invoice for an invoice credit paid in full says so and asks for nothing" do
    invoice = invoices(:sakura_january)
    invoice.payments.create! kind: :credit, amount: 247_500, stripe_payment_intent_id: "pi_credit"
    invoice.update_columns status: "paid", paid_amount: 247_500, paid_on: invoice.issue_date
    attach_fake_deliverables invoice

    { "ja" => "お支払いは完了しております", "en" => "this invoice with ¥247,500 of your credit" }.each do |locale, paid_line|
      invoice.update_columns locale: locale
      email = InvoiceMailer.send_invoice(invoice)

      [ email.html_part.decoded, email.text_part.decoded ].each do |body|
        assert_includes body, paid_line, locale
        assert_not_includes body, "/pay/", locale
        assert_not_includes body, invoice.due_date.to_s, locale
        assert_not_includes body, businesses(:default).bank_name, locale
      end
      assert_equal 2, email.attachments.size
    end
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

  def partial_payment(received:, remaining:)
    { amount_received: received, amount_remaining: remaining,
      instructions_url: "https://payments.stripe.com/bank_transfers/instructions/test_example",
      bank_details: { bank_name: "Example Bank", branch_name: "Sample Branch", account_type: "futsu",
                      account_number: "7654321", account_holder_name: "Example Consulting" } }
  end
end
