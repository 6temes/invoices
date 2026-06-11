class ExtraHoursController < ApplicationController
  before_action :set_client
  before_action :set_extra_hour, only: %i[edit update destroy]

  def new
    @extra_hour = @client.extra_hours.build performed_on: Date.current
  end

  def create
    @extra_hour = @client.extra_hours.build extra_hour_params
    if @extra_hour.save
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to client_path(@client), notice: "Extra hours logged." }
      end
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @extra_hour.update extra_hour_params
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to client_path(@client), notice: "Extra hours updated." }
      end
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @extra_hour.destroy
    @destroyed = @extra_hour.destroyed?
    @error_message = @extra_hour.errors.full_messages.to_sentence unless @destroyed

    respond_to do |format|
      format.turbo_stream
      format.html do
        redirect_to client_path(@client),
          @destroyed ? { notice: "Extra hours deleted." } : { alert: @error_message }
      end
    end
  end

  private

  def set_client
    @client = Client.find params[:client_id]
  end

  def set_extra_hour
    @extra_hour = @client.extra_hours.find params[:id]
  end

  def extra_hour_params
    params.expect(extra_hour: [ :performed_on, :description, :hours, :github_url ])
  end
end
