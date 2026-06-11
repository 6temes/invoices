require "test_helper"

class RetainersControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:daniel)
    @client = clients(:acme)
    @retainer = retainers(:acme_active)
  end

  test "show displays retainer" do
    get client_retainer_path(@client, @retainer)
    assert_response :success
  end

  test "new renders form" do
    get new_client_retainer_path(@client)
    assert_response :success
  end

  test "create saves retainer and closes active one" do
    assert_difference "Retainer.count" do
      post client_retainers_path(@client), params: {
        retainer: {
          monthly_hours: 15,
          monthly_amount: 150000,
          hourly_rate: 10000,
          starts_on: Date.current
        }
      }
    end
    assert_redirected_to client_path(@client)
    assert @retainer.reload.ends_on.present?
  end

  test "edit renders form" do
    get edit_client_retainer_path(@client, @retainer)
    assert_response :success
  end

  test "update changes retainer" do
    patch client_retainer_path(@client, @retainer), params: {
      retainer: { monthly_hours: 20 }
    }
    assert_redirected_to client_path(@client)
    assert_equal 20, @retainer.reload.monthly_hours
  end

  test "create with invalid data does not close active retainer" do
    active = @client.active_retainer

    post client_retainers_path(@client), params: { retainer: {
      monthly_amount: nil,
      monthly_hours: nil,
      hourly_rate: nil,
      starts_on: Date.current
    } }

    assert_response :unprocessable_entity
    if active
      assert_nil active.reload.ends_on
    end
  end

  test "destroy removes retainer" do
    assert_difference "Retainer.count", -1 do
      delete client_retainer_path(@client, @retainer)
    end
    assert_redirected_to client_path(@client)
  end
end
