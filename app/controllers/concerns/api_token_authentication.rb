module ApiTokenAuthentication
  extend ActiveSupport::Concern

  included do
    class_attribute :api_token_purpose
    before_action :authenticate_token
  end

  class_methods do
    def requires_api_token(purpose)
      self.api_token_purpose = purpose.to_s
    end
  end

  private

  def authenticate_token
    token = request.headers["Authorization"]&.delete_prefix("Bearer ")
    @api_token = ApiToken.find_by_token(token)

    if @api_token.nil?
      response.headers["WWW-Authenticate"] = bearer_challenge(token)
      render json: { error: "Unauthorized" }, status: :unauthorized
    elsif @api_token.purpose != api_token_purpose
      render json: { error: "Forbidden" }, status: :forbidden
    else
      @api_token.touch_last_used
    end
  end

  def bearer_challenge(token)
    token.present? ? 'Bearer error="invalid_token"' : "Bearer"
  end
end
