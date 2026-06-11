require "application_system_test_case"

class AuthenticationSystemTest < ApplicationSystemTestCase
  test "login page renders" do
    visit new_session_path
    assert_field "Email"
    assert_field "Password"
    assert_button "Sign in"
  end

  test "login with valid credentials" do
    visit new_session_path
    fill_in "Email", with: "daniel@6temes.cat"
    fill_in "Password", with: "password"
    click_on "Sign in"
    assert_css ".main-nav"
  end

  test "unauthenticated user is redirected to login" do
    visit invoices_path
    assert_current_path new_session_path
  end
end
