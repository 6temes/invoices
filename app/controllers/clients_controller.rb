class ClientsController < ApplicationController
  before_action :set_client, only: %i[show edit update destroy]

  def index
    @clients = Client.includes(:retainers).order(:name)
  end

  def show
    @retainers = @client.retainers.order(starts_on: :desc)
    @unbilled_extra_hours = @client.extra_hours.unbilled.order(performed_on: :desc)
  end

  def new
    @client = Client.new
    @client.build_address
  end

  def create
    @client = Client.new client_params
    if @client.save
      redirect_to @client, notice: "Client created."
    else
      @client.build_address unless @client.address
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @client.build_address unless @client.address
  end

  def update
    if @client.update client_params
      redirect_to @client, notice: "Client updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @client.destroy
      redirect_to clients_path, notice: "Client deleted."
    else
      redirect_to @client, alert: @client.errors.full_messages.to_sentence
    end
  end

  private

  def set_client
    @client = Client.includes(:address).find params[:id]
  end

  def client_params
    params.expect(client: [
      :contact_name, :email, :locale, :name, :payment_method, :payment_terms_days, :github_repos_text, :tax_registration_number,
      address_attributes: [ :id, :country_code, :postal_code, :administrative_area,
                            :locality, :sublocality, :street, :extended, :_destroy ]
    ])
  end
end
