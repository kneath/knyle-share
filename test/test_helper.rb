ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "minitest/mock"

module ActiveSupport
  class TestCase
    include ActiveJob::TestHelper

    # SQLite is the default datastore for this project, and parallel writes in
    # the test suite quickly hit busy locks once integration coverage grows.
    parallelize(workers: 1)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
    setup do
      clear_active_job_queues
    end

    teardown do
      clear_active_job_queues
    end

    private

    def clear_active_job_queues
      return unless ActiveJob::Base.queue_adapter.is_a?(ActiveJob::QueueAdapters::TestAdapter)

      clear_enqueued_jobs
      clear_performed_jobs
    end
  end
end
