module Admin
  class ProtectedController < BaseController
    before_action :require_admin!
  end
end
