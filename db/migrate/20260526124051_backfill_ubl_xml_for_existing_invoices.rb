class BackfillUblXmlForExistingInvoices < ActiveRecord::Migration[8.1]
  def up
    Invoice.where(status: %w[sent paid]).includes(:line_items, client: :address).find_each do |invoice|
      next if invoice.ubl_xml.attached?

      xml_string = UblInvoiceBuilder.new(invoice).to_xml
      invoice.ubl_xml.attach(
        io: StringIO.new(xml_string),
        filename: "invoice_#{invoice.invoice_number}.xml",
        content_type: "application/xml"
      )
    end
  end

  def down
    Invoice.where(status: %w[sent paid]).find_each do |invoice|
      invoice.ubl_xml.purge if invoice.ubl_xml.attached?
    end
  end
end
