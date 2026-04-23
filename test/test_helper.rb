ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require_relative "test_helpers/session_test_helper"

# Minitest 6 removed the built-in stub/mock helpers. Provide a tiny replacement
# good enough to swap class/module methods during a block.
module TestStubbing
  def stub_method(object, method_name, value)
    singleton = object.singleton_class
    original = singleton.instance_method(method_name)
    singleton.send(:define_method, method_name) { |*_, **__| value }
    yield
  ensure
    singleton.send(:define_method, method_name, original) if original
  end
end

ActiveSupport::TestCase.include TestStubbing

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
  end
end
