module Admin
  class ApiTokensController < ProtectedController
    before_action :set_api_token, only: :revoke

    def index
      @new_api_token = ApiToken.new
      @api_tokens = ordered_api_tokens
    end

    def create
      @api_token = ApiToken.new(api_token_params)
      @api_token.validate

      if @api_token.errors.include?(:label) || @api_token.errors.include?(:slug_prefix)
        @new_api_token = @api_token
        @api_tokens = ordered_api_tokens
        render :index, status: :unprocessable_entity
        return
      end

      @api_token, @issued_token = ApiToken.issue!(label: @api_token.label, slug_prefix: @api_token.slug_prefix)
      @new_api_token = ApiToken.new
      @api_tokens = ordered_api_tokens
      flash.now[:notice] = "API token created. Copy it now. You will not be able to see it again."
      render :index, status: :created
    end

    def revoke
      if @api_token.active?
        @api_token.revoke!
        redirect_to admin_api_tokens_path, notice: "Revoked #{@api_token.label}."
      else
        redirect_to admin_api_tokens_path, alert: "#{@api_token.label} is already revoked."
      end
    end

    private

    def set_api_token
      @api_token = ApiToken.find(params[:id])
    end

    def ordered_api_tokens
      ApiToken.order(created_at: :desc)
    end

    def api_token_params
      params.fetch(:api_token, ActionController::Parameters.new).permit(:label, :slug_prefix)
    end
  end
end
