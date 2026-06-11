require "application_system_test_case"

class ClientsSystemTest < ApplicationSystemTestCase
  setup do
    stub_request(:get, /zipcloud\.ibsnet\.co\.jp/).to_return(
      status: 200,
      headers: { "Content-Type" => "application/json" },
      body: { status: 200, results: nil }.to_json
    )
    sign_in
  end

  test "index page lists clients" do
    visit clients_path
    assert_text "Clients"
    assert_link "New client"
  end

  test "new client form renders all fields" do
    visit new_client_path
    assert_field "Company name"
    assert_field "Contact name"
    assert_field "Email"
    assert_selector "select[name='client[locale]']"
    assert_selector "select[name='client[payment_method]']"
    assert_field "Payment terms (days)"
  end

  test "create and view client" do
    visit new_client_path
    assert_field "Company name"

    fill_in "Company name", with: "Test Client Co"
    fill_in "Contact name", with: "Jane Doe"
    fill_in "Email", with: "test@example.com"
    fill_in "Payment terms (days)", with: "30"
    # Fill address fields (postal code last to avoid auto-fill overwriting)
    fill_in "Prefecture", with: "東京都"
    fill_in "City", with: "千代田区"
    fill_in "Neighborhood", with: "丸の内"
    fill_in "Street", with: "1-1"
    fill_in "Postal code", with: "100-0001"

    click_button "Save"

    # After successful create, should redirect to show page
    assert_text "Client created."
    assert_text "Test Client Co"
    assert_link "Edit"
    assert_link "Create retainer"
    assert_link "Log extra hours"
  end

  test "client show displays retainer and extra hours sections" do
    visit client_path(clients(:acme))
    assert_text clients(:acme).name
    assert_text "Active Retainer"
    assert_text "Unbilled Extra Hours"
  end

  test "create retainer for client" do
    # End the existing retainer so we can create a new one
    retainers(:fuji_active).update! ends_on: 1.day.ago

    visit new_client_retainer_path(clients(:fuji))

    fill_in "Monthly amount (¥)", with: "300000"
    fill_in "Monthly hours", with: "20"
    fill_in "Hourly rate for extras (¥)", with: "12000"
    click_button "Save"

    assert_text "Retainer created"
    assert_text "Web development and maintenance"
    assert_text "300,000"
  end

  test "log extra hours from client page" do
    visit new_client_extra_hour_path(clients(:acme))

    fill_in "Hours", with: "2.5"
    fill_in "Description (optional — ticket reference)", with: "#999 — QA test entry"
    click_button "Save"

    visit client_path(clients(:acme))

    within "#unbilled_extra_hours" do
      assert_text "#999 — QA test entry"
      assert_text "2.5"
    end
  end
end
