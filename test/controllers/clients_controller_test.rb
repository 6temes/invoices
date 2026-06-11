require "test_helper"

class ClientsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:daniel)
  end

  test "index lists clients" do
    get clients_path
    assert_response :success
  end

  test "show displays client" do
    get client_path(clients(:acme))
    assert_response :success
  end

  test "new renders form" do
    get new_client_path
    assert_response :success
  end

  test "create saves a valid client" do
    assert_difference "Client.count" do
      post clients_path, params: {
        client: {
          name: "New Client",
          contact_name: "Jane Doe",
          email: "new@example.com",
          locale: "en",
          payment_method: "bank_transfer",
          payment_terms_days: 30,
          address_attributes: { country_code: "JP", postal_code: "100-0001", locality: "千代田区", administrative_area: "東京都" }
        }
      }
    end
    assert_redirected_to client_path(Client.last)
  end

  test "create with invalid params renders new" do
    assert_no_difference "Client.count" do
      post clients_path, params: { client: { name: "" } }
    end
    assert_response :unprocessable_entity
  end

  test "edit renders form" do
    get edit_client_path(clients(:acme))
    assert_response :success
  end

  test "update changes client" do
    patch client_path(clients(:acme)), params: {
      client: { name: "Acme Updated" }
    }
    assert_redirected_to client_path(clients(:acme))
    assert_equal "Acme Updated", clients(:acme).reload.name
  end

  test "destroy removes client" do
    client = Client.create!(name: "Deletable", contact_name: "Del Person", email: "del@test.com", locale: :en, payment_method: :bank_transfer, payment_terms_days: 30, address_attributes: { country_code: "JP", postal_code: "100-0001", locality: "千代田区", administrative_area: "東京都" })
    assert_difference "Client.count", -1 do
      delete client_path(client)
    end
    assert_redirected_to clients_path
  end

  test "requires authentication" do
    sign_out
    get clients_path
    assert_redirected_to new_session_path
  end
end
