module Webui::BuildresultHelper
  def arch_repo_table_cell(repo, arch, package_name, status = nil, enable_help = true)
    status ||= @statushash[repo][arch][package_name] || { 'package' => package_name }
    status_id = valid_xml_id("id-#{package_name}_#{repo}_#{arch}")
    link_title = status['details']
    if status['code']
      code = status['code']
      theclass = 'status_' + code.gsub(/[- ]/, '_')
      # special case for scheduled jobs with constraints limiting the workers a lot
      theclass = 'status_scheduled_warning' if code == 'scheduled' && link_title.present?
    else
      code = ''
      theclass = ' '
    end

    content_tag(:td, class: [theclass, 'buildstatus', 'nowrap']) do
      if code.in?(['-', 'unresolvable', 'blocked', 'excluded', 'scheduled'])
        concat(link_to(code, '#', title: link_title, id: status_id, class: code))
      else
        concat(link_to(code.gsub(/\s/, '&nbsp;'),
                       package_live_build_log_path(project: @project.to_s, package: package_name, repository: repo, arch: arch),
                       title: link_title, rel: 'nofollow'))
      end

      if enable_help && status['code']
        concat(' ')
        concat(sprite_tag('help', title: Buildresult.status_description(status['code'])))
      end
    end
  end

  # NOTE: There is a JavaScript version of this method in project_monitor.js
  def webui2_arch_repo_table_cell(repo, arch, package_name, status = nil, enable_help = true)
    status ||= @statushash[repo][arch][package_name] || { 'package' => package_name }
    status_id = valid_xml_id("id-#{package_name}_#{repo}_#{arch}")
    link_title = status['details']
    code = ''
    theclass = ' '

    if status['code']
      code = status['code']
      theclass = "build-state-#{code}"
      # special case for scheduled jobs with constraints limiting the workers a lot
      theclass = 'text-warning' if code == 'scheduled' && link_title.present?
    end

    capture do
      if enable_help && status['code']
        concat(content_tag(:i, nil, class: ['fa', 'fa-question-circle', 'text-info', 'mr-1'],
                                    data: { content: Buildresult.status_description(status['code']), placement: 'top', toggle: 'popover' }))
      end
      if code.in?(['-', 'unresolvable', 'blocked', 'excluded', 'scheduled'])
        concat(link_to(code, 'javascript:void(0);', id: status_id, class: theclass, data: { content: link_title, placement: 'right', toggle: 'popover' }))
      else
        concat(link_to(code.gsub(/\s/, '&nbsp;'),
                       package_live_build_log_path(project: @project.to_s, package: package_name, repository: repo, arch: arch),
                       data: { content: link_title, placement: 'right', toggle: 'popover' }, rel: 'nofollow', class: theclass))
      end
    end
  end
end
