class ListInvoicesTool < MCP::Tool
  tool_name "list_invoices"
  description "List a year's issued invoices (never drafts), ordered by issue date. Filter by client or status."
  input_schema(
    properties: {
      year: { type: "integer", description: "Issue-date year" },
      client_id: { type: "integer" },
      status: { type: "string", enum: Invoice.statuses.keys - [ "draft" ] }
    },
    required: [ "year" ]
  )
  annotations read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: false

  def self.call(year:, server_context:, client_id: nil, status: nil)
    invoices = Invoice.issued.for_year(year).includes(:client).order(:issue_date, :invoice_number)
    invoices = invoices.where(client_id:) if client_id
    invoices = invoices.where(status:) if status

    MCP::Tool::Response.new([ { type: "text", text: { invoices: invoices.map { summary(it) } }.to_json } ])
  end

  def self.summary(invoice)
    invoice.slice(*%w[ id invoice_number issue_date due_date billing_month status subtotal tax_rate tax_amount total paid_on paid_amount ])
      .merge("client" => invoice.client.slice("id", "name"))
  end
end
