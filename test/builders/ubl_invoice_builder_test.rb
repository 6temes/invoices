require "test_helper"

class UblInvoiceBuilderTest < ActiveSupport::TestCase
  setup do
    @invoice = invoices(:acme_january)
    @invoice_ja = invoices(:sakura_january)
  end

  test "generates well-formed XML" do
    xml = UblInvoiceBuilder.new(@invoice).to_xml
    doc = Nokogiri::XML(xml)
    assert_empty doc.errors
  end

  test "generates valid XML for bank_transfer invoice" do
    xml = UblInvoiceBuilder.new(@invoice).to_xml
    doc = Nokogiri::XML(xml)

    assert_equal "urn:peppol:pint:billing-1@jp-1", doc.at_xpath("//cbc:CustomizationID", ubl_namespaces).text
    assert_equal "urn:peppol:bis:billing", doc.at_xpath("//cbc:ProfileID", ubl_namespaces).text
    assert_equal "380", doc.at_xpath("//cbc:InvoiceTypeCode", ubl_namespaces).text
    assert_equal "JPY", doc.at_xpath("//cbc:DocumentCurrencyCode", ubl_namespaces).text
    assert_equal "42", doc.at_xpath("//cbc:PaymentMeansCode", ubl_namespaces).text
  end

  test "generates valid XML for credit_card invoice" do
    xml = UblInvoiceBuilder.new(@invoice_ja).to_xml
    doc = Nokogiri::XML(xml)

    assert_equal "48", doc.at_xpath("//cbc:PaymentMeansCode", ubl_namespaces).text
    assert_nil doc.at_xpath("//cac:PayeeFinancialAccount", ubl_namespaces)
  end

  test "seller party contains qualified invoice registration number" do
    xml = UblInvoiceBuilder.new(@invoice).to_xml
    doc = Nokogiri::XML(xml)

    supplier = doc.at_xpath("//cac:AccountingSupplierParty/cac:Party", ubl_namespaces)
    endpoint = supplier.at_xpath("cbc:EndpointID", ubl_namespaces)
    assert_equal "T1234567890123", endpoint.text
    assert_equal "0221", endpoint["schemeID"]

    company_id = supplier.at_xpath("cac:PartyTaxScheme/cbc:CompanyID", ubl_namespaces)
    assert_equal "T1234567890123", company_id.text
  end

  test "buyer party contains corporate number when present" do
    clients(:acme).update! tax_registration_number: "1234567890123"
    xml = UblInvoiceBuilder.new(@invoice.reload).to_xml
    doc = Nokogiri::XML(xml)

    customer = doc.at_xpath("//cac:AccountingCustomerParty/cac:Party", ubl_namespaces)
    endpoint = customer.at_xpath("cbc:EndpointID", ubl_namespaces)
    assert_equal "1234567890123", endpoint.text
    assert_equal "0147", endpoint["schemeID"]
  end

  test "buyer uses email as endpoint when no tax registration number" do
    clients(:acme).update! tax_registration_number: nil
    xml = UblInvoiceBuilder.new(@invoice.reload).to_xml
    doc = Nokogiri::XML(xml)

    customer = doc.at_xpath("//cac:AccountingCustomerParty/cac:Party", ubl_namespaces)
    endpoint = customer.at_xpath("cbc:EndpointID", ubl_namespaces)
    assert_equal "billing@acme.example.com", endpoint.text
    assert_equal "EM", endpoint["schemeID"]

    assert_nil customer.at_xpath("cac:PartyTaxScheme", ubl_namespaces)
  end

  test "buyer reference defaults to billing period" do
    xml = UblInvoiceBuilder.new(@invoice).to_xml
    doc = Nokogiri::XML(xml)
    assert_equal "2026-01", doc.at_xpath("//cbc:BuyerReference", ubl_namespaces).text
  end

  test "buyer reference falls back to issue date when billing month is nil" do
    @invoice.update_columns billing_month: nil
    xml = UblInvoiceBuilder.new(@invoice.reload).to_xml
    doc = Nokogiri::XML(xml)
    assert_equal "2026-02", doc.at_xpath("//cbc:BuyerReference", ubl_namespaces).text
  end

  test "invoice period derives from billing month" do
    xml = UblInvoiceBuilder.new(@invoice).to_xml
    doc = Nokogiri::XML(xml)

    period = doc.at_xpath("//cac:InvoicePeriod", ubl_namespaces)
    assert_equal "2026-01-01", period.at_xpath("cbc:StartDate", ubl_namespaces).text
    assert_equal "2026-01-31", period.at_xpath("cbc:EndDate", ubl_namespaces).text
  end

  test "retainer line item uses unit code C62" do
    xml = UblInvoiceBuilder.new(@invoice).to_xml
    doc = Nokogiri::XML(xml)

    quantity = doc.at_xpath("//cac:InvoiceLine/cbc:InvoicedQuantity", ubl_namespaces)
    assert_equal "C62", quantity["unitCode"]
  end

  test "all monetary amounts are integers" do
    xml = UblInvoiceBuilder.new(@invoice).to_xml
    doc = Nokogiri::XML(xml)

    doc.xpath("//*[@currencyID]", ubl_namespaces).each do |element|
      assert_match(/\A\d+\z/, element.text, "#{element.name} should be an integer but was #{element.text}")
    end
  end

  test "tax total contains correct amounts" do
    xml = UblInvoiceBuilder.new(@invoice).to_xml
    doc = Nokogiri::XML(xml)

    tax_total = doc.at_xpath("//cac:TaxTotal", ubl_namespaces)
    assert_equal "10000", tax_total.at_xpath("cbc:TaxAmount", ubl_namespaces).text

    subtotal = tax_total.at_xpath("cac:TaxSubtotal", ubl_namespaces)
    assert_equal "100000", subtotal.at_xpath("cbc:TaxableAmount", ubl_namespaces).text
    assert_equal "S", subtotal.at_xpath("cac:TaxCategory/cbc:ID", ubl_namespaces).text
    assert_equal "10", subtotal.at_xpath("cac:TaxCategory/cbc:Percent", ubl_namespaces).text
  end

  test "monetary total contains correct amounts" do
    xml = UblInvoiceBuilder.new(@invoice).to_xml
    doc = Nokogiri::XML(xml)

    total = doc.at_xpath("//cac:LegalMonetaryTotal", ubl_namespaces)
    assert_equal "100000", total.at_xpath("cbc:LineExtensionAmount", ubl_namespaces).text
    assert_equal "100000", total.at_xpath("cbc:TaxExclusiveAmount", ubl_namespaces).text
    assert_equal "110000", total.at_xpath("cbc:TaxInclusiveAmount", ubl_namespaces).text
    assert_equal "110000", total.at_xpath("cbc:PayableAmount", ubl_namespaces).text
  end

  test "raises Error when client has no address" do
    @invoice.client.address.destroy
    @invoice.client.reload

    assert_raises UblInvoiceBuilder::Error do
      UblInvoiceBuilder.new(@invoice)
    end
  end

  test "raises Error when business has no address" do
    Business.instance.address.destroy
    Business.instance.reload

    assert_raises UblInvoiceBuilder::Error do
      UblInvoiceBuilder.new(@invoice)
    end
  end

  test "raises Error when business has no tax registration number" do
    Business.instance.stubs(:tax_registration_number).returns(nil)

    assert_raises UblInvoiceBuilder::Error do
      UblInvoiceBuilder.new(@invoice)
    end
  end

  test "extra hours line item uses unit code HUR" do
    extra_line = @invoice.line_items.create!(
      item_type: "Service",
      description: "Extra development hours",
      quantity: 2.5,
      unit_price: 10000,
      amount: 25000,
      origin: :extra_hours
    )

    xml = UblInvoiceBuilder.new(@invoice.reload).to_xml
    doc = Nokogiri::XML(xml)

    lines = doc.xpath("//cac:InvoiceLine", ubl_namespaces)
    extra_xml_line = lines.last
    quantity = extra_xml_line.at_xpath("cbc:InvoicedQuantity", ubl_namespaces)
    assert_equal "HUR", quantity["unitCode"]
    assert_equal "2.5", quantity.text

    extra_line.destroy!
  end

  test "generates valid XML for Japanese locale invoice" do
    xml = UblInvoiceBuilder.new(@invoice_ja).to_xml
    doc = Nokogiri::XML(xml)
    assert_empty doc.errors
    assert_equal "48", doc.at_xpath("//cbc:PaymentMeansCode", ubl_namespaces).text
  end

  test "validates against external JP PINT validator" do
    skip "External validation — set RUN_EXTERNAL_VALIDATION=1 to enable" unless ENV["RUN_EXTERNAL_VALIDATION"]

    WebMock.allow_net_connect!
    xml = UblInvoiceBuilder.new(@invoice).to_xml
    vesid = "org.peppol.pint.jp:invoice:1.1.2"

    errors = if ENV["PHORM_URL"]
      validate_with_phorm xml, vesid:
    else
      validate_with_helger xml, vesid:
    end

    assert_empty errors, "JP PINT validation errors:\n#{errors.join("\n")}"
  ensure
    WebMock.disable_net_connect! allow_localhost: true
  end

  private

  def validate_with_phorm(xml_string, vesid:)
    require "net/http"
    require "uri"
    require "json"

    uri = URI("#{ENV["PHORM_URL"]}/api/validate")
    http = Net::HTTP.new(uri.host, uri.port)
    http.open_timeout = 10
    http.read_timeout = 60

    request = Net::HTTP::Post.new(uri)
    request["Content-Type"] = "application/xml"
    request["Accept"] = "application/json"
    request["X-VESID"] = vesid
    request.body = xml_string

    response = http.request(request)

    unless response.content_type&.include?("json")
      skip "phorm returned unexpected response (#{response.code}): #{response.body[0..100]}"
    end

    result = JSON.parse response.body

    errors = []
    items = result["resultItems"] || result["items"] || []
    items.each do |item|
      level = item["errorLevel"] || item["severity"]
      next unless %w[ERROR FATAL].include? level
      errors << "[#{item["ruleID"] || item["test"]}] #{item["errorText"]} (at #{item["errorFieldName"] || item["errorLocation"]})"
    end
    errors
  rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNREFUSED => e
    skip "phorm validation service unreachable: #{e.message}"
  end

  def validate_with_helger(xml_string, vesid:)
    require "net/http"
    require "uri"

    soap_body = <<~SOAP
      <?xml version="1.0" encoding="UTF-8"?>
      <soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/"
                        xmlns:ws="http://peppol.helger.com/ws/documentvalidationservice/201701/">
        <soapenv:Body>
          <ws:validateRequestInput>
            <ws:VESID>#{vesid}</ws:VESID>
            <ws:XML><![CDATA[#{xml_string}]]></ws:XML>
          </ws:validateRequestInput>
        </soapenv:Body>
      </soapenv:Envelope>
    SOAP

    uri = URI("https://peppol.helger.com/wsdvs")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 10
    http.read_timeout = 30

    request = Net::HTTP::Post.new(uri.path)
    request["Content-Type"] = "text/xml; charset=utf-8"
    request["SOAPAction"] = ""
    request.body = soap_body

    response = http.request(request)
    doc = Nokogiri::XML(response.body)

    doc.remove_namespaces!
    errors = []
    doc.xpath("//Item[ErrorLevel[text()='ERROR' or text()='FATAL']]").each do |item|
      error_text = item.at_xpath("ErrorText")&.text
      error_id = item.at_xpath("Test")&.text
      location = item.at_xpath("ErrorLocation")&.text
      errors << "[#{error_id}] #{error_text} (at #{location})"
    end
    errors
  rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNREFUSED => e
    skip "Helger validation service unreachable: #{e.message}"
  end

  def ubl_namespaces
    {
      "cbc" => "urn:oasis:names:specification:ubl:schema:xsd:CommonBasicComponents-2",
      "cac" => "urn:oasis:names:specification:ubl:schema:xsd:CommonAggregateComponents-2"
    }
  end
end
