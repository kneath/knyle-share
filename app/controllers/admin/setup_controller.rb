module Admin
  class SetupController < BaseController
    before_action :redirect_if_claimed!

    def show
      @validation_result = SetupValidation::Result.pending
    end

    def validate
      @validation_result = SetupValidation.new.call
      render :show, status: @validation_result.passed? ? :ok : :unprocessable_entity
    end

    private

    def redirect_if_claimed!
      return unless installation.claimed?

      redirect_to(admin_signed_in? ? admin_bundles_path : admin_login_path)
    end
  end
end
