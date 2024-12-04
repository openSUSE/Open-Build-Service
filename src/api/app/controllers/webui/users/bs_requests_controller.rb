module Webui
  module Users
    class BsRequestsController < WebuiController
      before_action :require_login
      before_action :set_user

      include Webui::RequestsFilter

      REQUEST_METHODS = {
        'all_requests_table' => :requests,
        'requests_out_table' => :outgoing_requests,
        'requests_declined_table' => :declined_requests,
        'requests_in_table' => :incoming_requests,
        'reviews_in_table' => :involved_reviews
      }.freeze

      def index
        if Flipper.enabled?(:request_index, User.session)
          set_filter_involvement
          set_filter_state
          set_filter_action_type
          set_filter_creators

          filter_requests
          set_selected_filter

          # TODO: Temporarily disable list of creators due to performance issues
          # @bs_requests_creators = @bs_requests.distinct.pluck(:creator)
          @bs_requests = @bs_requests.order('number DESC').page(params[:page])
          @bs_requests = @bs_requests.includes(:bs_request_actions, :comments, :reviews)
          @bs_requests = @bs_requests.includes(:labels) if Flipper.enabled?(:labels, User.session)
        else
          index_legacy
        end
      end

      private

      def filter_requests
        if params[:requests_search_text].present?
          initial_bs_requests = filter_by_text(params[:requests_search_text])
          params[:ids] = filter_by_involvement(@filter_involvement).ids
        else
          initial_bs_requests = filter_by_involvement(@filter_involvement)
        end

        params[:creator] = @filter_creators if @filter_creators.present?
        params[:states] = @filter_state if @filter_state.present?
        params[:types] = @filter_action_type if @filter_action_type.present?

        @bs_requests = BsRequest::FindFor::Query.new(params, initial_bs_requests).all
      end

      def filter_by_involvement(filter_involvement)
        case filter_involvement
        when 'all'
          User.session.requests
        when 'incoming'
          User.session.incoming_requests
        when 'outgoing'
          User.session.outgoing_requests
        end
      end

      def set_selected_filter
        @selected_filter = { involvement: @filter_involvement, action_type: @filter_action_type, search_text: params[:requests_search_text],
                             state: @filter_state, creators: @filter_creators }
      end

      def set_user
        @user_or_group = User.session
      end

      def request_method
        REQUEST_METHODS[params[:dataTableId]] || :requests
      end

      # TODO: Remove this old index action when request_index feature is rolled-over
      def index_legacy
        parsed_params = BsRequest::DataTable::ParamsParser.new(params).parsed_params
        requests_query = BsRequest::DataTable::FindForUserOrGroupQuery.new(@user_or_group, request_method, parsed_params)
        @requests_data_table = BsRequest::DataTable::Table.new(requests_query, parsed_params[:draw])

        respond_to do |format|
          format.json { render 'webui/shared/bs_requests/index' }
        end
      end
    end
  end
end
