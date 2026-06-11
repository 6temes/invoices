class PostalCodeLookupsController < ApplicationController
  rate_limit to: 30, within: 1.minute, only: :show

  POSTAL_CODE_PATTERN = /\A\d{3}-?\d{4}\z/

  def show
    postal_code = params[:postal_code].to_s
    unless postal_code.match?(POSTAL_CODE_PATTERN)
      return render json: { error: "invalid postal code" }, status: :unprocessable_entity
    end

    result = ZipcloudGateway.lookup postal_code
    render json: result
  rescue ZipcloudGateway::NotFoundError
    render json: { error: "not found" }, status: :not_found
  rescue ZipcloudGateway::ServerError, Faraday::Error => e
    Rails.error.report e
    render json: { error: "lookup unavailable" }, status: :service_unavailable
  end
end
