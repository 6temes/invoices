require "test_helper"
require "puma/configuration"
require_relative "../../config/worktree"

class WorktreeTest < ActiveSupport::TestCase
  # Accepts any configuration call and keeps what was assigned, so development.rb can be
  # evaluated against a fixture root without booting a second app.
  class ConfigRecorder < BasicObject
    def initialize
      @values = {}
    end

    def method_missing(name, *args)
      if name.end_with?("=")
        @values[name.to_s.chomp("=").to_sym] = args.first
      else
        @values[name] ||= ConfigRecorder.new
      end
    end

    def respond_to_missing?(*) = true
  end

  test "a linked worktree is named after the SHA-256 of its path" do
    in_checkout(linked: true) do |root|
      File.stubs(:realpath).with(root).returns("/srv/worktrees/app/feature-x")

      assert_equal "4399c230", Worktree.identity(root)
      assert_equal 3692, Worktree.port(root, 3000)
      assert_equal "app_test_wt_4399c230", Worktree.database_name("app_test", root)
    end
  end

  test "the main checkout keeps the default port and database name" do
    in_checkout(linked: false) do |root|
      assert_nil Worktree.identity(root)
      assert_equal 3000, Worktree.port(root, 3000)
      assert_equal "app_test", Worktree.database_name("app_test", root)
    end
  end

  test "a linked worktree port stays within 3100 to 3899" do
    Dir.mktmpdir do |dir|
      ports = Array.new(200) do |i|
        root = File.join(dir, "feature-#{i}")
        Dir.mkdir(root)
        File.write(File.join(root, ".git"), "")
        Worktree.port(root, 3000)
      end

      assert_empty(ports.reject { it.in?(3100..3899) })
    end
  end

  test "puma binds the derived port in a linked worktree" do
    in_checkout(linked: true) do |root|
      with_port(nil) do
        assert_equal Worktree.port(root, 3000), puma_port(root)
      end
    end
  end

  test "puma binds an explicit PORT over the derived port" do
    in_checkout(linked: true) do |root|
      with_port("4567") do
        assert_equal 4567, puma_port(root)
      end
    end
  end

  test "puma binds 3000 in the main checkout" do
    in_checkout(linked: false) do |root|
      with_port(nil) do
        assert_equal 3000, puma_port(root)
      end
    end
  end

  test "development mailer links use the derived port in a linked worktree" do
    in_checkout(linked: true) do |root|
      assert_equal Worktree.port(root, 3000), development_mailer_url_options(root)[:port]
    end
  end

  test "development mailer links use 3000 in the main checkout" do
    in_checkout(linked: false) do |root|
      assert_equal 3000, development_mailer_url_options(root)[:port]
    end
  end

  private

  def development_mailer_url_options(root)
    development_rb = Rails.root.join("config/environments/development.rb")
    app = Struct.new(:config) { def configure(&) = instance_eval(&) }.new(ConfigRecorder.new)
    Rails.stubs(:application).returns(app)
    Rails.stubs(:root).returns(Pathname(root))

    load development_rb
    app.config.action_mailer.default_url_options
  end

  def in_checkout(linked:)
    Dir.mktmpdir do |root|
      git = File.join(root, ".git")
      linked ? File.write(git, "gitdir: /elsewhere\n") : Dir.mkdir(git)
      yield root
    end
  end

  # Copies puma.rb into the fixture because it finds the checkout from its own __dir__.
  def puma_port(root)
    config_dir = File.join(root, "config")
    Dir.mkdir(config_dir)
    FileUtils.cp(Rails.root.join("config/puma.rb"), config_dir)
    FileUtils.ln_s(Rails.root.join("config/worktree.rb"), config_dir)

    puma = Puma::Configuration.new(config_files: [ "#{config_dir}/puma.rb" ])
    URI(puma.clamp[:binds].sole).port
  end

  def with_port(value)
    original = ENV.fetch("PORT", nil)
    ENV["PORT"] = value
    yield
  ensure
    ENV["PORT"] = original
  end
end
