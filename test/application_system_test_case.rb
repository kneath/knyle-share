require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  parallelize(workers: 1)

  self.use_transactional_tests = false

  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1400 ]

  Capybara.server = :puma, { Silent: true }
  Capybara.server_host = "127.0.0.1"
  Capybara.server_port = 4010
end
