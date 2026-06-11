require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 900 ] do |driver_option|
    driver_option.add_argument("--disable-back-forward-cache")
    driver_option.add_argument("--disable-dev-shm-usage") if ENV["CI"]
  end

  setup do
    # Generous retry budget: the suite runs single-process against one headless
    # Chrome, so assertions race rendering when the machine is loaded (tests pass
    # in isolation but flake in the full run). A higher ceiling only costs time on
    # genuine failures; passing assertions still return as soon as they match.
    Capybara.default_max_wait_time = ENV["CI"] ? 10 : 5
  end

  private

  def visit(...)
    super
    wait_for_page_ready
  end

  # Wait until the page's importmap-loaded JS is interactive before a test touches
  # it. visit() returns once the HTML is parsed, but Turbo and the Stimulus
  # controllers load as separate async module requests afterwards — clicking a
  # link or firing a Stimulus action before they're wired up is the root cause of
  # this suite's historical flakiness.
  #
  # We poll for: document fully loaded, Turbo present (so Turbo Drive intercepts
  # link clicks), Stimulus present, and every on-page controller connected. A
  # transient JavascriptError (JS context torn down mid-navigation) means "not
  # ready yet" and is retried per-poll — it must never abandon the whole wait,
  # which is exactly the bug that let tests race ahead. The 15s cap is headroom
  # for slow CI loads; the common case exits in well under a second.
  def wait_for_page_ready
    Timeout.timeout(15) do
      sleep 0.05 until page_ready?
    end
  rescue Timeout::Error
    # Genuinely stuck (>15s) — proceed and let assertions surface the real failure.
    nil
  end

  def page_ready?
    page.evaluate_script(<<~JS)
      document.readyState === 'complete' &&
      typeof window.Turbo !== 'undefined' &&
      typeof window.Stimulus !== 'undefined' &&
      [...document.querySelectorAll('[data-controller]')].every(el =>
        el.dataset.controller.split(' ').every(id =>
          window.Stimulus.getControllerForElementAndIdentifier(el, id)
        )
      )
    JS
  rescue Selenium::WebDriver::Error::JavascriptError
    false
  end

  # Set session cookie directly — avoids flaky form interactions with Turbo Drive.
  # Every test calls visit() after sign_in, so we only need the cookie set.
  def sign_in
    session = users(:daniel).sessions.create! user_agent: "System Test", ip_address: "127.0.0.1"

    cookie_jar = ActionDispatch::TestRequest.create.cookie_jar
    cookie_jar.signed[:session_id] = session.id

    # Call page.visit directly to bypass wait_for_stimulus on this throwaway page.
    page.visit new_session_path

    page.driver.browser.manage.add_cookie(
      name: "session_id",
      value: cookie_jar[:session_id],
      path: "/"
    )
  end
end
