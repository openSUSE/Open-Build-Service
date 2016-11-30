module Webui::LoadBuildresults
  def fill_status_cache
    @repohash = Hash.new
    @statushash = Hash.new
    @packagenames = Array.new
    @repostatushash = Hash.new
    @repostatusdetailshash = Hash.new
    @failures = 0

    @buildresult.elements('result') do |result|
      @resultvalue = result
      repo = result['repository']
      arch = result['arch']

      next unless @repo_filter.nil? || @repo_filter.include?(repo)
      next unless @arch_filter.nil? || @arch_filter.include?(arch)

      @repohash[repo] ||= Array.new
      @repohash[repo] << arch

      # package status cache
      @statushash[repo] ||= Hash.new
      stathash = @statushash[repo][arch] = Hash.new

      result.elements('status') do |status|
        stathash[status['package']] = status
        @failures += 1 if %w(unresolvable failed broken).include? status['code']
      end
      @packagenames << stathash.keys

      # repository status cache
      @repostatushash[repo] ||= Hash.new
      @repostatusdetailshash[repo] ||= Hash.new

      if result.has_key? 'state'
        if result.has_key? 'dirty'
          @repostatushash[repo][arch] = 'outdated_' + result['state']
        else
          @repostatushash[repo][arch] = result['state']
        end
        if result.has_key? 'details'
          @repostatusdetailshash[repo][arch] = result['details']
        end
      end
    end
  end
end
