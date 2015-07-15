require_dependency 'activexml/activexml'

CONFIG['source_protocol'] ||= 'http'
CONFIG['api_relative_url_root'] ||= ''

map = ActiveXML::setup_transport_backend(CONFIG['source_protocol'], CONFIG['source_host'], CONFIG['source_port'])

map.connect :directory, 'rest:///source/:project/:package?:expand&:rev&:meta&:linkrev&:emptylink&:view&:extension&:lastworking&:withlinked&:deleted'
map.connect :jobhistory, 'rest:///build/:project/:repository/:arch/_jobhistory?:package&:limit&:code'

map.connect :collection, 'rest:///search/:what?:match',
            id: 'rest:///search/:what/id?:match',
            package: 'rest:///search/package?:match',
            project: 'rest:///search/project?:match'

map.connect :fileinfo, 'rest:///build/:project/:repository/:arch/:package/:filename?:view'

map.connect :buildresult, 'rest:///build/:project/_result?:view&:package&:code&:lastbuild&:arch&:repository'

map.connect :builddepinfo, 'rest:///build/:project/:repository/:arch/_builddepinfo?:package&:limit&:code'

map.connect :statistic, 'rest:///build/:project/:repository/:arch/:package/_statistics'

map.connect :service, 'rest:///source/:project/:package/_service?:user'

if defined?(Rack::MiniProfiler)
  ::Rack::MiniProfiler.profile_method(ActiveXML::Transport, :http_do) do |method,url|
    if url.kind_of? String
      "#{method.to_s.upcase} #{url}"
    else
      "#{method.to_s.upcase} #{url.path}?#{url.query}"
    end
  end
end

map = ActiveXML::setup_transport_api(CONFIG['frontend_protocol'], CONFIG['frontend_host'], CONFIG['frontend_port'], CONFIG['api_relative_url_root'])

map.connect :webuiproject, 'rest:///source/:name/_meta?:view',
            :delete => 'rest:///source/:name?:force',
            :issues => 'rest:///source/:name?view=issues'

map.connect :webuirequest, 'rest:///request/:id', :create => 'rest:///request?cmd=create'

map.set_additional_header( 'User-Agent', "obs-webui/#{CONFIG['version']}" )
map.set_additional_header( 'Accept', 'application/xml' )
