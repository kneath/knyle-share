module Admin
  class SetupController < BaseController
    def show
      redirect_to(admin_signed_in? ? admin_bundles_path : admin_login_path) and return if installation.claimed?

      @validation_result = SetupValidation::Result.pending
    end

    def validate
      redirect_to(admin_signed_in? ? admin_bundles_path : admin_login_path) and return if installation.claimed?

      @validation_result = SetupValidation.new.call
      render :show, status: @validation_result.passed? ? :ok : :unprocessable_entity
    end
  end
end
