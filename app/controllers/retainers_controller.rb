class RetainersController < ApplicationController
  before_action :set_client
  before_action :set_retainer, only: %i[show edit update destroy]

  def show
  end

  def new
    @retainer = @client.retainers.build starts_on: Date.current
  end

  def create
    @retainer = @client.retainers.build retainer_params

    saved = Retainer.transaction do
      @client.active_retainer&.update!(ends_on: @retainer.starts_on - 1.day) if @retainer.starts_on
      @retainer.save.tap { |ok| raise ActiveRecord::Rollback unless ok }
    end

    if saved
      redirect_to client_path(@client), notice: "Retainer created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @retainer.update retainer_params
      redirect_to client_path(@client), notice: "Retainer updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @retainer.destroy
    redirect_to client_path(@client), notice: "Retainer deleted."
  end

  private

  def set_client
    @client = Client.find params[:client_id]
  end

  def set_retainer
    @retainer = @client.retainers.find params[:id]
  end

  def retainer_params
    params.expect(retainer: [
      :monthly_hours, :monthly_amount,
      :hourly_rate, :includes_infrastructure, :starts_on, :ends_on
    ])
  end
end
