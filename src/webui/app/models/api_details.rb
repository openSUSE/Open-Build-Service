class ApiDetails

  def self.logger
    Rails.logger
  end

  def self.find(info, opts)
    uri = "/webui/"
    uri += 
      case info 
      when :project_infos then "project_infos?project=:project"
      when :project_requests then "project_requests?project=:project"
      when :person_requests_that_need_work then "person_requests_that_need_work?login=:login"
      when :request_show then "request_show?id=:id"
      when :person_involved_requests then "person_involved_requests?login=:login"
      when :request_ids then "request_ids?ids=:ids"
      else raise "no valid info #{info}"
      end
    uri = URI(uri)
    transport = ActiveXML::transport
    uri = transport.substitute_uri(uri, opts)
    transport.replace_server_if_needed(uri)
    data = transport.direct_http(uri)
    data = ActiveSupport::JSON.decode(data)
    logger.debug "data #{JSON.pretty_generate(data)}"
    data
  end
end

