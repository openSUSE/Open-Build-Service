class Webui::SubscriptionsController < Webui::WebuiController
  before_action :require_admin

  def index
    @subscriptions_form = subscriptions_form

    # TODO: Remove the statement after migration is finished
    switch_to_webui2 if Rails.env.development? || Rails.env.test?
  end

  def update
    subscriptions_form.update!(params[:subscriptions])
    flash[:notice] = 'Notifications settings updated'
  rescue ActiveRecord::RecordInvalid
    flash[:error] = 'Notifications settings could not be updated due to an error'
  ensure
    redirect_to action: :index
  end

  private

  def subscriptions_form
    EventSubscription::Form.new
  end
end
