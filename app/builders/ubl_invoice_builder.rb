class UblInvoiceBuilder
  class Error < StandardError; end

  NAMESPACES = {
    "xmlns" => "urn:oasis:names:specification:ubl:schema:xsd:Invoice-2",
    "xmlns:cac" => "urn:oasis:names:specification:ubl:schema:xsd:CommonAggregateComponents-2",
    "xmlns:cbc" => "urn:oasis:names:specification:ubl:schema:xsd:CommonBasicComponents-2"
  }.freeze

  CUSTOMIZATION_ID = "urn:peppol:pint:billing-1@jp-1"
  PROFILE_ID = "urn:peppol:bis:billing"

  UNIT_CODES = {
    "retainer" => "C62",
    "extra_hours" => "HUR",
    "manual" => "C62"
  }.freeze

  PAYMENT_MEANS_CODES = {
    "bank_transfer" => "42",
    "credit_card" => "48"
  }.freeze

  def initialize(invoice)
    @invoice = invoice
    @business = Business.instance
    validate!
  end

  def to_xml
    Nokogiri::XML::Builder.new(encoding: "UTF-8") { |xml|
      xml.Invoice(NAMESPACES) do
        header xml
        invoice_period xml
        supplier_party xml
        customer_party xml
        payment_means xml
        tax_total xml
        monetary_total xml
        invoice_lines xml
      end
    }.to_xml
  end

  private

  def validate!
    raise Error, "Invoice must have line items" unless @invoice.line_items.any?
    raise Error, "Business must have an address" unless @business.address.present?
    raise Error, "Business must have a tax registration number" unless @business.tax_registration_number.present?
    raise Error, "Client must have an address" unless @invoice.client.address.present?
  end

  def header(xml)
    xml["cbc"].CustomizationID CUSTOMIZATION_ID
    xml["cbc"].ProfileID PROFILE_ID
    xml["cbc"].ID @invoice.invoice_number.to_s
    xml["cbc"].IssueDate @invoice.issue_date.iso8601
    xml["cbc"].DueDate @invoice.due_date.iso8601
    xml["cbc"].InvoiceTypeCode "380"
    xml["cbc"].DocumentCurrencyCode "JPY"
    xml["cbc"].BuyerReference buyer_reference
  end

  def invoice_period(xml)
    period_month = @invoice.billing_month || @invoice.issue_date
    start_date = period_month.beginning_of_month
    end_date = period_month.end_of_month

    xml["cac"].InvoicePeriod do
      xml["cbc"].StartDate start_date.iso8601
      xml["cbc"].EndDate end_date.iso8601
    end
  end

  def supplier_party(xml)
    xml["cac"].AccountingSupplierParty do
      xml["cac"].Party do
        xml["cbc"].EndpointID @business.tax_registration_number, schemeID: "0221"
        xml["cac"].PartyIdentification do
          xml["cbc"].ID @business.tax_registration_number, schemeID: "0221"
        end
        postal_address xml, @business.address
        xml["cac"].PartyTaxScheme do
          xml["cbc"].CompanyID @business.tax_registration_number
          xml["cac"].TaxScheme { xml["cbc"].ID "VAT" }
        end
        xml["cac"].PartyLegalEntity do
          xml["cbc"].RegistrationName @business.name
        end
      end
    end
  end

  def customer_party(xml)
    client = @invoice.client

    xml["cac"].AccountingCustomerParty do
      xml["cac"].Party do
        buyer_endpoint xml, client
        buyer_identification xml, client
        postal_address xml, client.address
        buyer_tax_scheme xml, client
        xml["cac"].PartyLegalEntity do
          xml["cbc"].RegistrationName client.name
        end
      end
    end
  end

  def buyer_endpoint(xml, client)
    if client.tax_registration_number.present?
      xml["cbc"].EndpointID client.tax_registration_number, schemeID: "0147"
    else
      xml["cbc"].EndpointID client.email, schemeID: "EM"
    end
  end

  def buyer_identification(xml, client)
    return unless client.tax_registration_number.present?

    xml["cac"].PartyIdentification do
      xml["cbc"].ID client.tax_registration_number, schemeID: "0147"
    end
  end

  def buyer_tax_scheme(xml, client)
    return unless client.tax_registration_number.present?

    xml["cac"].PartyTaxScheme do
      xml["cbc"].CompanyID client.tax_registration_number
      xml["cac"].TaxScheme { xml["cbc"].ID "VAT" }
    end
  end

  def postal_address(xml, address)
    street = address_street(address)
    xml["cac"].PostalAddress do
      xml["cbc"].StreetName street if street.present?
      xml["cbc"].CityName address.locality if address.locality.present?
      xml["cbc"].PostalZone address.postal_code
      xml["cbc"].CountrySubentity address.administrative_area if address.administrative_area.present?
      xml["cac"].Country do
        xml["cbc"].IdentificationCode address.country_code
      end
    end
  end

  def address_street(address)
    [ address.sublocality, address.street, address.extended ].compact_blank.join(" ")
  end

  def payment_means(xml)
    xml["cac"].PaymentMeans do
      xml["cbc"].PaymentMeansCode PAYMENT_MEANS_CODES.fetch(@invoice.client.payment_method) { raise Error, "Unknown payment method: #{@invoice.client.payment_method}" }
      xml["cbc"].PaymentID @invoice.invoice_number.to_s

      if @invoice.client.bank_transfer?
        xml["cac"].PayeeFinancialAccount do
          xml["cbc"].ID @business.bank_account_number
          xml["cbc"].Name @business.bank_account_holder
          xml["cbc"].AccountTypeCode @business.bank_account_type
          xml["cac"].FinancialInstitutionBranch do
            xml["cbc"].ID [ @business.bank_code, @business.bank_branch_code ].compact.join(":")
            xml["cbc"].Name [ @business.bank_name, @business.bank_branch ].join(" ")
          end
        end
      end
    end
  end

  def tax_total(xml)
    xml["cac"].TaxTotal do
      amount_element xml, "TaxAmount", @invoice.tax_amount
      xml["cac"].TaxSubtotal do
        amount_element xml, "TaxableAmount", @invoice.subtotal
        amount_element xml, "TaxAmount", @invoice.tax_amount
        xml["cac"].TaxCategory do
          xml["cbc"].ID "S"
          xml["cbc"].Percent @invoice.tax_rate.to_i.to_s
          xml["cac"].TaxScheme { xml["cbc"].ID "VAT" }
        end
      end
    end
  end

  def monetary_total(xml)
    xml["cac"].LegalMonetaryTotal do
      amount_element xml, "LineExtensionAmount", @invoice.subtotal
      amount_element xml, "TaxExclusiveAmount", @invoice.subtotal
      amount_element xml, "TaxInclusiveAmount", @invoice.total
      amount_element xml, "PayableAmount", @invoice.total
    end
  end

  def invoice_lines(xml)
    @invoice.line_items.each_with_index do |line_item, index|
      xml["cac"].InvoiceLine do
        xml["cbc"].ID (index + 1).to_s
        xml["cbc"].InvoicedQuantity format_quantity(line_item.quantity), unitCode: UNIT_CODES.fetch(line_item.origin) { raise Error, "Unknown line item origin: #{line_item.origin}" }
        amount_element xml, "LineExtensionAmount", line_item.amount
        xml["cac"].Item do
          xml["cbc"].Name line_item.description
          xml["cac"].ClassifiedTaxCategory do
            xml["cbc"].ID "S"
            xml["cbc"].Percent @invoice.tax_rate.to_i.to_s
            xml["cac"].TaxScheme { xml["cbc"].ID "VAT" }
          end
        end
        xml["cac"].Price do
          amount_element xml, "PriceAmount", line_item.unit_price
        end
      end
    end
  end

  def amount_element(xml, element_name, value)
    xml["cbc"].send element_name, value.to_i.to_s, currencyID: "JPY"
  end

  def format_quantity(quantity)
    quantity == quantity.to_i ? quantity.to_i.to_s : quantity.to_s("F")
  end

  def buyer_reference
    month = @invoice.billing_month || @invoice.issue_date
    month.strftime("%Y-%m")
  end
end
