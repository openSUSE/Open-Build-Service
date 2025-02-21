module Webui
  module Users
    class BsRequestsController < WebuiController
      before_action :redirect_legacy
      before_action :require_login
      before_action :set_user
      before_action :set_bs_requests

      include Webui::RequestsFilter

      REQUEST_METHODS = {
        'all_requests_table' => :requests,
        'requests_out_table' => :outgoing_requests,
        'requests_declined_table' => :declined_requests,
        'requests_in_table' => :incoming_requests,
        'reviews_in_table' => :involved_reviews
      }.freeze

      def index
        respond_to do |format|
          format.html do
            # FIXME: Once we roll out request_index filter_requests should become a before_action
            filter_requests
            @bs_requests = @bs_requests.page(params[:page])
          end
          # TODO: Remove this old index action when request_index feature is rolled-over
          format.json do
            parsed_params = BsRequest::DataTable::ParamsParser.new(params).parsed_params
            requests_query = BsRequest::DataTable::FindForUserOrGroupQuery.new(@user_or_group, request_method, parsed_params)
            @requests_data_table = BsRequest::DataTable::Table.new(requests_query, parsed_params[:draw])

            render 'webui/shared/bs_requests/index'
          end
        end
      end

      private

      def set_bs_requests
        return unless Flipper.enabled?(:request_index, User.session)

        @bs_requests = User.session.bs_requests
      end

      def filter_direction
        @filter_direction = params[:direction].presence
        return unless %w[incoming outgoing].include?(@filter_direction)

        @bs_requests = case @filter_direction
                       when 'incoming'
                         @bs_requests.where(reviews: { user: User.session })
                                     .or(@bs_requests.where(reviews: { group: User.session.groups }))
                                     .or(@bs_requests.where(reviews: { project: User.session.involved_projects }))
                                     .or(@bs_requests.where(reviews: { package: User.session.involved_packages }))
                                     .or(@bs_requests.where(bs_request_actions: { target_project_id: User.session.involved_projects }))
                                     .or(@bs_requests.where(bs_request_actions: { target_package_id: User.session.involved_packages }))
                       when 'outgoing'
                         @bs_requests.where(creator: User.session)
                                     .or(@bs_requests.where(bs_request_actions: { source_project_id: User.session.involved_projects }))
                                     .or(@bs_requests.where(bs_request_actions: { source_package_id: User.session.involved_packages }))
                       end
      end

      def filter_by_direction_staging_project(direction)
        case direction
        when 'all'
          User.session.requests.where(staging_project: staging_projects)
        when 'incoming'
          User.session.incoming_requests.where(staging_project: staging_projects)
        when 'outgoing'
          User.session.outgoing_requests.where(staging_project: staging_projects)
        end
      end

      def set_user
        @user_or_group = User.session
      end

      def request_method
        REQUEST_METHODS[params[:dataTableId]] || :requests
      end

      def redirect_legacy
        redirect_to(my_tasks_path) unless Flipper.enabled?(:request_index, User.session) || request.format.json?
      end
    end
  end
end
