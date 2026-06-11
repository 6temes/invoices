class BusinessesController < ApplicationController
  before_action :set_business

  def edit
  end

  def update
    if @business.update business_params
      redirect_to edit_business_path, notice: "Business settings updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_business
    @business = Business.instance
    @business.build_address unless @business.address
  end

  def business_params
    params.expect(business: [
      :name, :tax_registration_number,
      :bank_code, :bank_name, :bank_branch, :bank_branch_code, :bank_account_holder, :bank_account_type, :bank_account_number,
      :email, :tax_rate,
      address_attributes: [ :id, :country_code, :postal_code, :administrative_area,
                            :locality, :sublocality, :street, :extended ]
    ])
  end
end
