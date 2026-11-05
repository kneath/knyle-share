module Admin
  module Api
    module V1
      class TokensController < BaseController
        before_action :mark_api_token_used!

        def show
          render json: { slug_prefix: current_api_token.slug_prefix }
        end
      end
    end
  end
end
