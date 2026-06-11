class ApiTokensController < ApplicationController
  def create
    @token = Current.user.api_tokens.build token_params
    if @token.save
      redirect_to edit_business_path, flash: { token: @token.plain_token }
    else
      redirect_to edit_business_path, alert: "Could not create token."
    end
  end

  def destroy
    token = Current.user.api_tokens.find params[:id]
    token.destroy
    redirect_to edit_business_path, notice: "Token revoked."
  end

  private

  def token_params
    params.expect(api_token: [ :name ])
  end
end
