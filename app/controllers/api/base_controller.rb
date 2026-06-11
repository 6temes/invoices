module Api
  class BaseController < ActionController::API
    include PaperTrail::Rails::Controller

    rate_limit to: 60, within: 1.minute, by: -> { request.remote_ip }, with: -> {
      render json: { error: "Rate limit exceeded" }, status: :too_many_requests
    }

    before_action :authenticate_token

    private

    def authenticate_token
      token = request.headers["Authorization"]&.delete_prefix("Bearer ")
      @api_token = ApiToken.find_by_token(token)

      unless @api_token
        render json: { error: "Unauthorized" }, status: :unauthorized
        return
      end

      @api_token.touch_last_used
    end

    def user_for_paper_trail
      @api_token&.user_id
    end
  end
end
