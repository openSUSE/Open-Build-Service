require 'test_helper'

require 'benchmark'
require 'nokogiri'
require 'webui/home_controller'

class Webui::SpiderTest < Webui::IntegrationTest

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
      # that link is just a top ref
      next if link.end_with? '/package/rdiff'
      # admin can see even the hidden
      next if link.end_with? '/package/show/HiddenRemoteInstance'
      next if link.end_with? '/project/show/HiddenRemoteInstance'
      next if link.end_with? '/project/show/RemoteInstance'
      next if link.end_with? '/package/show/BaseDistro3/pack2'
      next if link.end_with? '/package/show/home:Iggy/TestPack'
      next if tag.content == 'show latest'
      unless @pages_visited.has_key? link
        @pages_to_visit[link] ||= [baseuri.to_s, tag.content]
      end
    end
  end

  def raiseit(message, url)
    # known issues
    return if url =~ %r{/package/binary/BinaryprotectedProject/.*}
    return if url =~ %r{/package/statistics/BinaryprotectedProject/.*}
    return if url =~ %r{/package/statistics/SourceprotectedProject/.*}
    return if url.end_with? '/package/binary/SourceprotectedProject/pack?arch=i586&filename=package-1.0-1.src.rpm&repository=repo'
    return if url =~ %r{/package/revisions/SourceprotectedProject.*}
    return if url.end_with? '/package/show/kde4/kdelibs?rev=1'
    return if url.end_with? '/package/show/SourceprotectedProject/target'
    return if url.end_with? '/package/users/SourceprotectedProject/pack'
    return if url.end_with? '/package/view_file/BaseDistro:Update/pack2?file=my_file&rev=1'
    return if url.end_with? '/package/view_file/Devel:BaseDistro:Update/pack2?file=my_file&rev=1'
    return if url.end_with? '/package/view_file/Devel:BaseDistro:Update/pack3?file=my_file&rev=1'
    return if url.end_with? '/package/view_file/LocalProject/remotepackage?file=my_file&rev=1'
    return if url.end_with? '/package/view_file/BaseDistro2.0:LinkedUpdateProject/pack2.linked?file=myfile&rev=1'
    return if url.end_with? '/package/view_file/BaseDistro2.0/pack2.linked?file=myfile&rev=1'
    return if url.end_with? '/package/view_file/BaseDistro2.0:LinkedUpdateProject/pack2.linked?file=package.spec&rev=1'
    return if url.end_with? '/package/view_file/BaseDistro2.0/pack2.linked?file=package.spec&rev=1'
    return if url.end_with? '/project/edit/RemoteInstance'
    return if url.end_with? '/project/meta/HiddenRemoteInstance'
    return if url.end_with? '/project/show/HiddenRemoteInstance'
    return if url.end_with? '/project/edit/HiddenRemoteInstance'
    return if url.end_with? '/home?user=unknown'

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
        puts "V #{theone} #{@pages_to_visit.length}/#{@pages_visited.keys.length+@pages_to_visit.length}"
        page.visit(theone)
        page.first(:id, 'header-logo')
      rescue Timeout::Error
        next
      rescue ActionController::RoutingError
        raiseit('routing error', theone)
        return
      end
      body = nil
      begin
        body = Nokogiri::HTML::Document.parse(page.source).root
      rescue Nokogiri::XML::SyntaxError
        #puts "HARDCORE!! #{theone}"
      end
      next unless body
      flashes = body.css('div#flash-messages div.ui-state-error')
      if !flashes.empty?
        raiseit("flash alert #{flashes.first.content.strip}", theone)
      end
      body.css('h1').each do |h|
        if h.content == 'Internal Server Error'
          raiseit('Internal Server Error', theone)
        end
      end
      body.css('h2').each do |h|
        if h.content == 'XML errors'
          raiseit('XML errors', theone)
        end
      end
      body.css('#exception-error').each do |e|
        raiseit("error '#{e.content}'", theone)
      end
      getlinks(theone, body)
    end
  end

  test 'spider anonymously' do
    return unless ENV['RUN_SPIDER']
    visit webui_engine.root_path
    @pages_to_visit = {page.current_url => [nil, nil]}
    @pages_visited = Hash.new

    crawl
    ActiveRecord::Base.clear_active_connections!
  end

  test 'spider as admin' do
    return unless ENV['RUN_SPIDER']
    login_king
    visit webui_engine.root_path
    @pages_to_visit = {page.current_url => [nil, nil]}
    @pages_visited = Hash.new

    crawl
    ActiveRecord::Base.clear_active_connections!
  end

end
