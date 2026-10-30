class GetInvoiceTool < MCP::Tool
  tool_name "get_invoice"
  description "Fetch one issued invoice by invoice number, with its line items and its PDF and UBL files when attached."
  input_schema(properties: { invoice_number: { type: "integer" } }, required: [ "invoice_number" ])
  annotations read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: false

  def self.call(invoice_number:, server_context:)
    invoice = Invoice.issued
      .includes(:line_items, :client, pdf_attachment: :blob, ubl_xml_attachment: :blob)
      .find_by(invoice_number:)
    return MCP::Tool::Response.new([ { type: "text", text: "Invoice #{invoice_number} not found" } ], error: true) unless invoice

    files = [ invoice.pdf, invoice.ubl_xml ].select(&:attached?)
    MCP::Tool::Response.new([ { type: "text", text: details(invoice).to_json }, *files.map { embedded(invoice, it) } ])
  end

  def self.details(invoice)
    invoice.slice(*ListInvoicesTool::INVOICE_FIELDS).merge(
      "client" => invoice.client.slice("id", "name", "tax_registration_number"),
      "line_items" => invoice.line_items.map { it.slice("item_type", "description", "quantity", "unit_price", "amount", "origin") },
      "files" => {
        "pdf" => { "attached" => invoice.pdf.attached?, "filename" => invoice.pdf.filename&.to_s },
        "ubl_xml" => { "attached" => invoice.ubl_xml.attached?, "filename" => invoice.ubl_xml.filename&.to_s }
      }
    )
  end

  # Tool::Response#to_h leaves content items as objects, and ActiveSupport would serialise
  # them with snake_case keys the client drops, so each one is converted here.
  def self.embedded(invoice, file)
    contents = MCP::Resource::BlobContents.new(
      uri: "invoices://invoices/#{invoice.invoice_number}/#{file.filename}",
      mime_type: file.content_type,
      data: Base64.strict_encode64(file.download)
    )
    MCP::Content::EmbeddedResource.new(contents).to_h
  end
end
