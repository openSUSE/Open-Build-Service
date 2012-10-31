class Patchinfo < ActiveXML::Node
  class << self
    def make_stub( opt )
      "<patchinfo/>"
    end
  end

  # FIXME: Layout and colors belong to CSS
  RATING_COLORS = {
    'low'       => 'green',
    'moderate'  => 'olive',
    'important' => 'red',
    'critical'  => 'maroon',
  }

  RATINGS = RATING_COLORS.keys

  CATEGORY_COLORS = {
    'recommended' => 'green',
    'security'    => 'maroon',
    'optional'    => 'olive',
    'feature'     => '',
  }

  # '' is a valid category
  CATEGORIES = [''].concat(CATEGORY_COLORS.keys)

  def save
    path = self.init_options[:package] ? "/source/#{self.init_options[:project]}/#{self.init_options[:package]}/_patchinfo" : "/source/#{self.init_options[:package]}/_patchinfo"
    begin
      frontend = ActiveXML::transport
      frontend.direct_http URI("#{path}"), :method => "POST", :data => self.dump_xml
      result = {:type => :note, :msg => "Patchinfo sucessfully updated!"}
    rescue ActiveXML::Transport::Error => e
      result = {:type => :error, :msg => "Saving Patchinfo failed: #{ActiveXML::Transport.extract_error_message( e )[0]}"}
    end

    return result
  end

  def issues
    issues = Patchinfo.find_cached(:issues, :project => self.init_options[:project], :package => self.init_options[:package])
    if issues
      return issues.each('issue')
    else
      return []
    end
  end

  def issues_by_tracker
    issues_by_tracker = {}
    self.issues.each do |issue|
      issues_by_tracker[issue.value('tracker')] ||= []
      issues_by_tracker[issue.value('tracker')] << issue
    end
    return issues_by_tracker
  end

  def is_maintainer? userid
    has_element? "person[@role='maintainer' and @userid = '#{userid}']"
  end

end
