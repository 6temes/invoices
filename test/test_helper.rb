ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "mocha/minitest"
require "webmock/minitest"

WebMock.disable_net_connect! allow_localhost: true
require_relative "test_helpers/session_test_helper"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    def attach_deliverables(invoice)
      invoice.pdf.attach io: StringIO.new("%PDF-1.4"), filename: "test.pdf", content_type: "application/pdf"
      invoice.ubl_xml.attach io: StringIO.new("<Invoice/>"), filename: "test.xml", content_type: "application/xml"
    end
  end
end
