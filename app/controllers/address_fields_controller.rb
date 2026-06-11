class AddressFieldsController < ApplicationController
  ALLOWED_OBJECT_NAMES = %w[client[address_attributes] business[address_attributes]].freeze

  def show
    @country_code = params[:country_code].presence || "JP"
    return head(:bad_request) unless @country_code.match?(/\A[A-Z]{2}\z/)

    @object_name = params[:object_name]
    return head(:bad_request) unless ALLOWED_OBJECT_NAMES.include?(@object_name)

    @address = Address.new(country_code: @country_code)

    render partial: @address.fields_partial, locals: {
      address: @address,
      object_name: @object_name,
      address_id: params[:address_id]
    }
  end
end
