# This job requests the source diff from the backend, which
# can take a long time depending on the differences. The next time a User views
# this BsRequest it's already available then. Kind of like warming up the diff
# 'cache' on the backend.
#
# triggered by RequestController#request_create when a BsRequest is created

class BsRequestActionWebuiInfosJob < ApplicationJob
  queue_as :quick

  def perform(request_action)
    # FIXME: This should work for BsRequest with a source on a remote instance.
    request_action.webui_infos unless request_action.is_from_remote?
  end
end
