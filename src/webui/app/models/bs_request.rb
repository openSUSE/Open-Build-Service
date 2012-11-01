class BsRequest < ActiveXML::Node

  class ListError < Exception; end
  class ModifyError < Exception; end

  default_find_parameter :id

  class << self
    def make_stub(opt)
      target_package = ""
      opt[:description] = "" if !opt.has_key? :description or opt[:description].nil?
      if opt[:targetpackage] and not opt[:targetpackage].empty?
        target_package = "package=\"#{opt[:targetpackage].to_xs}\""
      end

      # set request-specific options
      case opt[:type]
        when "submit" then
          # use source package name if no target package name is given for a submit request
          target_package = "package=\"#{opt[:package].to_xs}\"" if target_package.empty?
          # set target package is the same as the source package if no target package is specified
          revision_option = "rev=\"#{opt[:rev].to_xs}\"" unless opt[:rev].blank?
          action = "<source project=\"#{opt[:project]}\" package=\"#{opt[:package]}\" #{revision_option}/>"
          action += "<target project=\"#{opt[:targetproject].to_xs}\" #{target_package}/>"
          action += "<options><sourceupdate>#{opt[:sourceupdate]}</sourceupdate></options>" unless opt[:sourceupdate].blank?
        when "add_role" then
          action = "<group name=\"#{opt[:group]}\" role=\"#{opt[:role]}\"/>" unless opt[:group].blank?
          action = "<person name=\"#{opt[:person]}\" role=\"#{opt[:role]}\"/>" unless opt[:person].blank?
          action += "<target project=\"#{opt[:targetproject].to_xs}\" #{target_package}/>"
        when "set_bugowner" then
          action = "<person name=\"#{opt[:person]}\" role=\"#{opt[:role]}\"/>"
          action += "<target project=\"#{opt[:targetproject].to_xs}\" #{target_package}/>"
        when "change_devel" then
          action = "<source project=\"#{opt[:project]}\" package=\"#{opt[:package]}\"/>"
          action += "<target project=\"#{opt[:targetproject].to_xs}\" #{target_package}/>"
        when "maintenance_incident" then
          action = "<source project=\"#{opt[:project]}\" />"
          action += "<target project=\"#{opt[:targetproject].to_xs}\" />" unless opt[:targetproject].blank?
        when "maintenance_release" then
          action = "<source project=\"#{opt[:project]}\" />"
          action += "<target project=\"#{opt[:targetproject].to_xs}\" />" unless opt[:targetproject].blank?
        when "delete" then
          action = "<target project=\"#{opt[:targetproject].to_xs}\" #{target_package}/>"
      end
      # build the request XML
      reply = <<-EOF
        <request>
          <action type="#{opt[:type]}">
            #{action}
          </action>
          <state name="new"/>
          <description>#{opt[:description].to_xs}</description>
        </request>
      EOF
      return reply
    end

    def addReview(id, opts)
      opts = {:user => nil, :group => nil, :project => nil, :package => nil, :comment => nil}.merge opts

      transport ||= ActiveXML::transport
      path = "/request/#{id}?cmd=addreview"
      path << "&by_user=#{CGI.escape(opts[:user])}" unless opts[:user].blank?
      path << "&by_group=#{CGI.escape(opts[:group])}" unless opts[:group].blank?
      path << "&by_project=#{CGI.escape(opts[:project])}" unless opts[:project].blank?
      path << "&by_package=#{CGI.escape(opts[:package])}" unless opts[:package].blank?
      begin
        transport.direct_http URI("#{path}"), :method => "POST", :data => opts[:comment]
        BsRequest.free_cache(id)
        return true
      rescue ActiveXML::Transport::ForbiddenError => e
        message, _, _ = ActiveXML::Transport.extract_error_message e
        raise ModifyError, message
      rescue ActiveXML::Transport::NotFoundError => e
        message, _, _ = ActiveXML::Transport.extract_error_message e
        raise ModifyError, message
      end
    end

    def modifyReview(id, changestate, opts)
      unless (changestate=="accepted" || changestate=="declined")
        raise ModifyError, "unknown changestate #{changestate}"
      end

      transport ||= ActiveXML::transport
      path = "/request/#{id}?newstate=#{changestate}&cmd=changereviewstate"
      path << "&by_user=#{CGI.escape(opts[:user])}" unless opts[:user].blank?
      path << "&by_group=#{CGI.escape(opts[:group])}" unless opts[:group].blank?
      path << "&by_project=#{CGI.escape(opts[:project])}" unless opts[:project].blank?
      path << "&by_package=#{CGI.escape(opts[:package])}" unless opts[:package].blank?
      begin
        transport.direct_http URI("#{path}"), :method => "POST", :data => opts[:comment]
        BsRequest.free_cache(id)
        return true
      rescue ActiveXML::Transport::ForbiddenError, ActiveXML::Transport::NotFoundError, ActiveXML::Transport::Error => e
        message, _, _ = ActiveXML::Transport.extract_error_message e
        raise ModifyError, message
      end
    end

    def modify(id, changestate, opts)
      opts = {:superseded_by => nil, :force => false, :reason => ''}.merge opts
      if ["accepted", "declined", "revoked", "superseded", "new"].include?(changestate)
        transport ||= ActiveXML::transport
        path = "/request/#{id}?newstate=#{changestate}&cmd=changestate"
        path += "&superseded_by=#{opts[:superseded_by]}" unless opts[:superseded_by].blank?
        path += "&force=1" if opts[:force]
        begin
          transport.direct_http URI("#{path}"), :method => "POST", :data => opts[:reason].to_s
          BsRequest.free_cache(id)
          return true
        rescue ActiveXML::Transport::ForbiddenError, ActiveXML::Transport::NotFoundError => e
          message, _, _ = ActiveXML::Transport.extract_error_message e
          raise ModifyError, message
        end
      end
      raise ModifyError, "unknown changestate #{changestate}"
    end

    def set_incident(id, incident_project)
      begin
        path = "/request/#{id}?cmd=setincident&incident=#{incident_project}"
        transport ||= ActiveXML::transport
        transport.direct_http URI(path), :method => "POST", :data => ''
        BsRequest.free_cache(id)
        return true
      rescue ActiveXML::Transport::ForbiddenError, ActiveXML::Transport::NotFoundError, ActiveXML::Transport::Error => e
        message, _, _ = ActiveXML::Transport.extract_error_message e
        raise ModifyError, message
      end
      raise ModifyError, "Unable to merge with incident #{incident_project}"
    end

    def find_last_request(opts)
      unless opts[:targetpackage] and opts[:targetproject] and opts[:sourceproject] and opts[:sourcepackage]
        raise RuntimeError, "missing parameters"
      end
      pred = "(action/target/@package='#{opts[:targetpackage]}' and action/target/@project='#{opts[:targetproject]}' and action/source/@project='#{opts[:sourceproject]}' and action/source/@package='#{opts[:sourcepackage]}' and action/@type='submit')"
      requests = Collection.find_cached :what => :request, :predicate => pred
      last = nil
      requests.each_request do |r|
        last = r if not last or r.value(:id).to_i > last.value(:id).to_i
      end
      return last
    end

    def ids(ids)
      return [] if ids.blank?
      logger.debug "Fetching request list from api"
      ApiDetails.find(:request_ids, ids: ids.join(','))
    end

    def list(opts)
      unless opts[:states] or opts[:reviewstate] or opts[:roles] or opts[:types] or opts[:user] or opts[:project]
        raise RuntimeError, "missing parameters"
      end

      opts.delete(:types) if opts[:types] == 'all' # All types means don't pass 'type' to backend

      transport ||= ActiveXML::transport
      path = "/request?view=collection"
      path << "&states=#{CGI.escape(opts[:states])}" unless opts[:states].blank?
      path << "&roles=#{CGI.escape(opts[:roles])}" unless opts[:roles].blank?
      path << "&reviewstates=#{CGI.escape(opts[:reviewstates])}" unless opts[:reviewstates].blank?
      path << "&types=#{CGI.escape(opts[:types])}" unless opts[:types].blank? # the API want's to have it that way, sigh...
      path << "&user=#{CGI.escape(opts[:user])}" unless opts[:user].blank?
      path << "&project=#{CGI.escape(opts[:project])}" unless opts[:project].blank?
      path << "&package=#{CGI.escape(opts[:package])}" unless opts[:package].blank?
      path << "&subprojects=1" if opts[:subprojects]
      begin
        logger.debug "Fetching request list from api"
        response = transport.direct_http URI("#{path}"), :method => "GET"
        return Collection.new(response).each # last statement, implicit return value of block, assigned to 'request_list' non-local variable
      rescue ActiveXML::Transport::Error => e
        message, _, _ = ActiveXML::Transport.extract_error_message e
        raise ListError, message
      end
    end

    def sorted_filenames_from_sourcediff(sourcediff)
      # Sort files into categories by their ending and add all of them to a hash. We
      # will later use the sorted and concatenated categories as key index into the per action file hash.
      changes_file_keys, spec_file_keys, patch_file_keys, other_file_keys = [], [], [], []
      files_hash, issues_hash = {}, {}

      sourcediff.files.each do |file|
        if file.new
          filename = file.new.name.to_s
        elsif file.old # in case of deleted files
          filename = file.old.name.to_s
        end
        if filename.include?('/')
          other_file_keys << filename
        else
          if filename.ends_with?('.spec')
            spec_file_keys << filename
          elsif filename.ends_with?('.changes')
            changes_file_keys << filename
          elsif filename.match(/.*.(patch|diff|dif)/)
            patch_file_keys << filename
          else
            other_file_keys << filename
          end
        end
        files_hash[filename] = file
      end

      if sourcediff.has_element?(:issues)
        sourcediff.issues.each do |issue|
          issues_hash[issue.value('label')] = Issue.find_cached(issue.value('name'), :tracker => issue.value('tracker'))
        end
      end

      parsed_sourcediff = {
        :old => sourcediff.old,
        :new => sourcediff.new,
        :filenames => changes_file_keys.sort + spec_file_keys.sort + patch_file_keys.sort + other_file_keys.sort,
        :files => files_hash,
        :issues => issues_hash
      }
      return parsed_sourcediff
    end
  end

  def history
    ret = []
    self.each_history do |h|
      ret << { :who => h.who, :when => Time.parse(h.when), :name => h.name, :comment => h.value(:comment) }
    end if self.has_element?(:history)
    h = self.state
    ret << { :who => h.who, :when => Time.parse(h.when), :name => h.name, :comment => h.value(:comment) }
    return ret
  end

  def reviewer_for_history_item(item)
    reviewer = ''
    if item.by_group
      reviewer = item.value('by_group')
    elsif item.by_project
      reviewer = item.value('by_project')
    elsif item.by_package
      reviewer = item.value('by_package')
    elsif item.by_user
      reviewer = item.value('by_user')
    end
    return reviewer
  end
end
