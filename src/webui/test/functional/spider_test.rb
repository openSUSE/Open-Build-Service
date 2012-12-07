require File.expand_path(File.dirname(__FILE__) + "/..") + "/test_helper"

require 'benchmark'
require 'nokogiri'

class SpiderTest < ActionDispatch::IntegrationTest

  def setup
    # only run one or the other spider test
    @run_admin = rand(10) < 5
    super
  end

  def getlinks(baseuri, body)
    # skip some uninteresting projects
    return if baseuri =~ %r{project=home%3Afred}
    return if baseuri =~ %r{project=home%3Acoolo}
    return if baseuri =~ %r{project=deleted}

    baseuri = URI.parse(baseuri)

    body.traverse do |tag|
      next unless tag.element? 
      next unless tag.name == 'a'
      next if tag.attributes['data-remote']
      next if tag.attributes['data-method']
      link = tag.attributes['href']
      begin
        link = baseuri.merge(link)
      rescue ArgumentError 
        # if merge does not like it, it's not a valid link
        next
      end
      link.fragment = nil
      link.normalize!
      next unless link.host == baseuri.host
      next unless link.port == baseuri.port
      link = link.to_s
      next if link =~ %r{/mini-profiler-resources}
      unless @pages_visited.has_key? link
        @pages_to_visit[link] ||= [baseuri.to_s, tag.content]
      end
    end
  end

  def raiseit(message, url)
    # known issues
    return if url =~ %r{/package/binary\?.*project=BinaryprotectedProject}
    return if url.end_with? "/package/files?package=target&project=SourceprotectedProject"
    return if url.end_with? "/package/rdiff"
    return if url.end_with? "/package/revisions?package=pack&project=SourceprotectedProject"
    return if url.end_with? "/package/users?package=pack&project=SourceprotectedProject"
    return if url.end_with? "/package/view_file?file=my_file&package=pack2&project=BaseDistro%3AUpdate&rev=1"
    return if url.end_with? "/package/view_file?file=my_file&package=pack2&project=Devel%3ABaseDistro%3AUpdate&rev=1"
    return if url.end_with? "/package/view_file?file=my_file&package=pack3&project=Devel%3ABaseDistro%3AUpdate&rev=1"
    return if url.end_with? "/package/view_file?file=my_file&package=remotepackage&project=LocalProject&rev=1"
    return if url.end_with? "/package/view_file?file=myfile&package=pack2_linked&project=BaseDistro2.0%3ALinkedUpdateProject&rev=1"
    return if url.end_with? "/package/view_file?file=myfile&package=pack2_linked&project=BaseDistro2.0&rev=1"
    return if url.end_with? "/package/view_file?file=package.spec&package=pack2_linked&project=BaseDistro2.0%3ALinkedUpdateProject&rev=1"
    return if url.end_with? "/package/view_file?file=package.spec&package=pack2_linked&project=BaseDistro2.0&rev=1"
    return if url.end_with? "/project/show?project=HiddenRemoteInstance"
    return if url.end_with? "/package/binary?arch=i586&filename=package-1.0-1.src.rpm&package=pack&project=SourceprotectedProject&repository=repo"
    return if url.end_with? "/project/meta?project=HiddenRemoteInstance"
    return if url.end_with? "/package/revisions?package=target&project=SourceprotectedProject"

    $stderr.puts "Found #{message} on #{url}, crawling path"
    indent = ' '
    while @pages_visited.has_key? url
      url, text = @pages_visited[url]
      break if url.blank?
      $stderr.puts "#{indent}#{url} ('#{text}')"
      indent += '  '
    end
    raise "Found #{message}"
  end

  def crawl
    while @pages_to_visit.length > 0
      theone = @pages_to_visit.keys.sort.first
      @pages_visited[theone] = @pages_to_visit[theone]
      @pages_to_visit.delete theone

      begin
        page.visit(theone)
        page.first(:id, 'header-logo')
      rescue Timeout::Error
        next
      rescue ActionController::RoutingError
        raiseit("routing error", theone)
        return
      end
      body = nil
      begin
        body = Nokogiri::XML::Document.parse(page.source, nil, nil, Nokogiri::XML::ParseOptions::STRICT).root
      rescue Nokogiri::XML::SyntaxError
        #puts "HARDCORE!! #{theone}"
      end
      next unless body
      flashes = body.css("div#flash-messages div.ui-state-error")
      if !flashes.empty?
        raiseit("flash alert #{flashes.first.content.strip}", theone)
      end
      body.css('h1').each do |h|
        if h.content == 'Internal Server Error'
          raiseit("Internal Server Error", theone)
        end
      end
      body.css('h2').each do |h|
	if h.content == 'XML errors'
          raiseit("XML errors", theone)
	end
      end
      body.css("#exception-error").each do |e|
        raiseit("error '#{e.content}'", theone)
      end
      getlinks(theone, body)
    end
  end

  test "spider anonymously" do
    return if @run_admin
    visit "/"
    @pages_to_visit = { page.current_url => [nil, nil] }
    @pages_visited = Hash.new
    
    crawl
  end

  test "spider as admin" do
    return unless @run_admin
    login_king
    visit "/"
    @pages_to_visit = { page.current_url => [nil, nil] }
    @pages_visited = Hash.new
    
    crawl
  end

end
