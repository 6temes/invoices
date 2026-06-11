require "test_helper"

class ExtraHoursControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:daniel)
    @client = clients(:acme)
  end

  test "new renders form" do
    get new_client_extra_hour_path(@client)
    assert_response :success
  end

  test "create saves extra hour" do
    assert_difference "ExtraHour.count" do
      post client_extra_hours_path(@client), params: {
        extra_hour: {
          hours: 1.5,
          performed_on: Date.current,
          description: "Bug fix"
        }
      }
    end
    assert_redirected_to client_path(@client)
  end

  test "create with invalid params renders new" do
    assert_no_difference "ExtraHour.count" do
      post client_extra_hours_path(@client), params: {
        extra_hour: { hours: 0, performed_on: "" }
      }
    end
    assert_response :unprocessable_entity
  end

  test "edit renders form" do
    extra = extra_hours(:acme_unbilled_with_desc)
    get edit_client_extra_hour_path(@client, extra)
    assert_response :success
  end

  test "update changes extra hour" do
    extra = extra_hours(:acme_unbilled_with_desc)
    patch client_extra_hour_path(@client, extra), params: {
      extra_hour: { hours: 3.0 }
    }
    assert_redirected_to client_path(@client)
    assert_equal 3.0, extra.reload.hours
  end

  test "destroy removes extra hour" do
    extra = extra_hours(:acme_unbilled_with_desc)
    assert_difference "ExtraHour.count", -1 do
      delete client_extra_hour_path(@client, extra)
    end
    assert_redirected_to client_path(@client)
  end
end
