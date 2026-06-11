class CloudflarePdfGateway
  ServerError = Class.new(StandardError)
  ClientError = Class.new(StandardError)

  def self.render(html)
    account_id = Rails.application.credentials.dig(:cloudflare, :account_id)

    response = connection.post(
      "/client/v4/accounts/#{account_id}/browser-rendering/pdf"
    ) do |req|
      req.body = { html: html }
    end

    return response.body if response.success?

    Rails.logger.error "[CloudflarePdfGateway] Failed (#{response.status}): #{response.body}"

    if response.status >= 500
      raise ServerError, "PDF generation failed (HTTP #{response.status})"
    else
      raise ClientError, "PDF generation failed (HTTP #{response.status})"
    end
  end

  def self.connection
    @_connection ||= Faraday.new(url: "https://api.cloudflare.com") do |f|
      f.request :json
      f.headers["Authorization"] = "Bearer #{Rails.application.credentials.dig(:cloudflare, :api_token)}"
      f.options.open_timeout = 10
      f.options.timeout = 30
      f.adapter Faraday.default_adapter
    end
  end
end
