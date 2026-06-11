class ZipcloudGateway
  BASE_URL = "https://zipcloud.ibsnet.co.jp"

  NotFoundError = Class.new(StandardError)
  ServerError = Class.new(StandardError)

  def self.lookup(postal_code)
    normalized = postal_code.to_s.delete("-")
    response = connection.get("/api/search", zipcode: normalized)

    raise ServerError, "zipcloud returned #{response.status}" unless response.success?

    body = begin
      JSON.parse(response.body)
    rescue JSON::ParserError => e
      raise ServerError, "invalid response from zipcloud: #{e.message}"
    end
    raise ServerError, body["message"] if body["status"].to_i != 200
    raise NotFoundError, "no results for #{postal_code}" if body["results"].blank?

    result = body["results"].first
    {
      administrative_area: result["address1"],
      locality: result["address2"],
      sublocality: result["address3"]
    }
  end

  def self.connection
    @_connection ||= Faraday.new(url: BASE_URL) do |f|
      f.options.open_timeout = 5
      f.options.timeout = 10
    end
  end
end
