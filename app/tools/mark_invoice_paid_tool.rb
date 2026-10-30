class MarkInvoicePaidTool < MCP::Tool
  tool_name "mark_invoice_paid"
  description "Mark a sent invoice as paid on the date the payment arrived. The client is emailed a receipt, as when marking it paid in the app."
  input_schema(
    properties: {
      invoice_number: { type: "integer" },
      paid_on: { type: "string", description: "Date the payment arrived, YYYY-MM-DD" }
    },
    required: %w[ invoice_number paid_on ]
  )
  annotations read_only_hint: false, destructive_hint: false, idempotent_hint: false, open_world_hint: true

  def self.call(invoice_number:, paid_on:, server_context:)
    invoice = Invoice.issued.find_by(invoice_number:)
    return error("Invoice #{invoice_number} not found") unless invoice
    return error("Invoice #{invoice_number} is #{invoice.status}; only sent invoices can be marked as paid") unless invoice.sent?

    invoice.mark_as_paid! paid_on: Date.iso8601(paid_on)
    MCP::Tool::Response.new([ { type: "text", text: invoice.slice(*ListInvoicesTool::INVOICE_FIELDS).to_json } ])
  rescue Date::Error
    error("paid_on must be a date in YYYY-MM-DD format")
  rescue ActiveRecord::RecordInvalid => e
    error(e.record.errors.full_messages.to_sentence)
  end

  def self.error(text)
    MCP::Tool::Response.new([ { type: "text", text: } ], error: true)
  end
end
