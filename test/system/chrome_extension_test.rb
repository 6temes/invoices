require "application_system_test_case"

class ChromeExtensionSystemTest < ApplicationSystemTestCase
  CONTENT_SCRIPT = Rails.root.join("chrome_extension/content.js").read

  test "the log hours popup keeps an issue title and client name as text" do
    title = %q(Fix "quotes" <b onmouseover="alert(1)">here</b>)
    client = %q(Example "Client" <img src=x>)

    visit new_session_path
    page.execute_script(<<~JS, title, client)
      const [title, client] = arguments
      history.pushState({}, '', '/example/repo/issues/12')
      window.chrome = { storage: { local: { get: async () => ({ apiUrl: 'https://invoices.example.com', apiToken: 'test' }) } } }
      window.fetch = async () => ({ json: async () => [ { id: 7, name: client, github_repos: [] } ] })
      document.body.insertAdjacentHTML('beforeend', '<h1 class="js-issue-title"></h1>')
      document.querySelector('.js-issue-title').textContent = title
    JS
    page.execute_script(CONTENT_SCRIPT)

    click_on "Log hours"

    within ".inv-popup" do
      assert_field with: "#12 — #{title}"
      assert_select with_options: [ client ]
      assert_no_selector "b, img"
    end
  end
end
