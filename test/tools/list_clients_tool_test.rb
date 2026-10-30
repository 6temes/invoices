require "test_helper"

class ListClientsToolTest < ActiveSupport::TestCase
  test "lists clients with their tax registration numbers" do
    clients = JSON.parse(ListClientsTool.call(server_context: {}).content.first[:text])["clients"]

    acme = clients.find { it["name"] == "Acme Corp." }
    sakura = clients.find { it["name"] == "桜テクノロジー株式会社" }
    assert_equal "T1234567890123", acme["tax_registration_number"]
    assert_nil sakura["tax_registration_number"]
  end
end
