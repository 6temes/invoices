require "test_helper"

class SeedsTest < ActiveSupport::TestCase
  # The seeds create the one Business themselves.
  setup { Business.destroy_all }

  test "seeds a sample login in a local environment" do
    assert_difference -> { User.count }, 1 do
      load_seeds
    end
  end

  test "seeds no login in production" do
    Rails.stubs(:env).returns ActiveSupport::EnvironmentInquirer.new("production")

    assert_no_difference -> { User.count } do
      load_seeds
    end
  end

  private

  def load_seeds
    capture_io { load Rails.root.join("db/seeds.rb") }
  end
end
