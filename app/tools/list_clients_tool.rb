class ListClientsTool < MCP::Tool
  tool_name "list_clients"
  description "List clients with the details freee needs to match or create a trading partner."
  annotations read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: false

  def self.call(server_context:)
    clients = Client.order(:name).map { it.slice(*%w[ id name tax_registration_number locale payment_method ]) }

    MCP::Tool::Response.new([ { type: "text", text: { clients: }.to_json } ])
  end
end
