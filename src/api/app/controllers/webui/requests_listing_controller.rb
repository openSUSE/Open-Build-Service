class Webui::RequestsListingController < Webui::WebuiController
  before_action :assign_attributes, :lockout_spiders
  before_action :require_login

  include Webui::RequestsFilter

  def index
    set_filter_involvement
    set_filter_state
    set_filter_action_type
    set_filter_creators

    filter_requests
    set_selected_filter

    @bs_requests = @bs_requests.order('number DESC').page(params[:page])
    @bs_requests_creators = @bs_requests.distinct.pluck(:creator)
  end

  private

  # Initialize shared attributes
  def assign_attributes
    @url = requests_path
  end

  def filter_requests
    params[:ids] = filter_by_involvement(@filter_involvement).ids
    params[:creator] = @filter_creators if @filter_creators.present?
    params[:states] = @filter_state if @filter_state.present?
    params[:types] = @filter_action_type if @filter_action_type.present?
    params[:search] = params[:requests_search_text] if params[:requests_search_text].present?

    @bs_requests = BsRequest::FindFor::Query.new(params).all
  end

  def set_selected_filter
    @selected_filter = { involvement: @filter_involvement, action_type: @filter_action_type, search_text: params[:requests_search_text],
                         state: @filter_state, creators: @filter_creators }
  end
end
