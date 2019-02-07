module Webui
  module Projects
    class BsRequestsController < WebuiController
      before_action :set_project

      def index
        parsed_params = BsRequest::DataTable::ParamsParserWithStateAndType.new(params).parsed_params
        requests_query = BsRequest::DataTable::FindForProjectQuery.new(@project, parsed_params)
        @requests_data_table = BsRequest::DataTable::Table.new(requests_query, params[:draw])

        respond_to do |format|
          if switch_to_webui2?
            format.json { render 'webui2/shared/bs_requests/index' }
          else
            format.json
          end
        end
        switch_to_webui2
      end
    end
  end
end
