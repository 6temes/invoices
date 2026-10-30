module Api
  class BaseController < ActionController::API
    include PaperTrail::Rails::Controller

    rate_limit to: 60, within: 1.minute, by: -> { request.remote_ip }, with: -> {
      render json: { error: "Rate limit exceeded" }, status: :too_many_requests
    }

    include ApiTokenAuthentication
    requires_api_token :chrome_extension

    before_action :set_paper_trail_whodunnit

    private

    def user_for_paper_trail
      @api_token&.user_id
    end
  end
end
