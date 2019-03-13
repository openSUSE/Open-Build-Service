module Webui::RequestHelper
  include Webui::UserHelper
  include Webui::WebuiHelper

  STATE_COLORS = {
    'new' => 'green',
    'accepted' => 'green',
    'revoked' => 'orange',
    'declined' => 'red',
    'superseded' => 'red'
  }.freeze

  STATE_BOOTSTRAP_ICONS = {
    'new' => 'fa-code-branch',
    'review' => 'fa-search',
    'accepted' => 'fa-check',
    'declined' => 'fa-hand-paper',
    'revoked' => 'fa-eraser',
    'superseded' => 'fa-plus'
  }.freeze

  AVAILABLE_TYPES = ['all', 'submit', 'delete', 'add_role', 'change_devel', 'maintenance_incident', 'maintenance_release'].freeze
  AVAILABLE_STATES = ['new or review', 'new', 'review', 'accepted', 'declined', 'revoked', 'superseded'].freeze

  def request_state_color(state)
    STATE_COLORS[state.to_s] || ''
  end

  def request_bootstrap_icon(state)
    STATE_BOOTSTRAP_ICONS[state.to_s] || ''
  end

  def new_or_update_request(row)
    if row.target_package_id || row.request_type != 'submit'
      row.request_type
    else
      "#{row.request_type} <small>(new package)</small>".html_safe
    end
  end

  def merge_opt(res, opt, value)
    res[opt] ||= value
    res[opt] = :multiple if value != res[opt]
  end

  def common_parts(req)
    Rails.cache.fetch([req, 'common_parts']) do
      res = {}
      res[:source_package] = nil
      res[:source_project] = nil
      res[:target_package] = nil
      res[:target_project] = nil
      res[:request_type] = nil

      req.bs_request_actions.each do |ae|
        merge_opt(res, :source_package, ae.source_package)
        merge_opt(res, :source_project, ae.source_project)
        merge_opt(res, :target_package, ae.target_package)
        merge_opt(res, :target_project, ae.target_project)
        merge_opt(res, :request_type, ae.action_type)
        res[:target_package_id] ||= ae.target_package_id
      end

      res[:request_type] = map_request_type(res[:request_type])
      res
    end
  end

  def map_request_type(type)
    # for a simplified view on a request, must be used only for lists
    case type
    when :change_devel then
      'chgdev'
    when :set_bugowner then
      'bugowner'
    when :add_role then
      'addrole'
    when :maintenance_incident then
      'incident'
    when :maintenance_release then
      'release'
    else
      type.to_s
    end
  end

  def priority_description(prio)
    case prio
    when 'low' then
      'Work on this request if nothing else needs to be done.'
    when 'moderate' then
      'Work on this request.'
    when 'important' then
      'Finish other requests you have begun, then work on this request.'
    when 'critical' then
      'Drop everything and work on this request.'
    end
  end

  def priority_number(prio)
    case prio
    when 'low' then
      '1'
    when 'moderate' then
      '2'
    when 'important' then
      '3'
    when 'critical' then
      '4'
    end
  end

  def target_project_link(row)
    result = ''
    if row.target_project
      if row.target_package && row.source_package != row.target_package
        result = project_or_package_link(project: row.target_project, package: row.target_package, trim_to: 40, short: true)
      else
        result = project_or_package_link(project: row.target_project, trim_to: 40, short: true)
      end
    end
    result
  end

  def calculate_filename(filename, file_element)
    return filename unless file_element['state'] == 'changed'
    return filename if file_element['old']['name'] == filename
    return "#{file_element['old']['name']} -> #{filename}"
  end

  def reviewer(review)
    return "#{review[:by_project]} / #{review[:by_package]}" if review[:by_package]
    review[:by_user] || review[:by_group] || review[:by_project]
  end

  def diff_data(action_type, sourcediff)
    diff = (action_type == :delete ? sourcediff['old'] : sourcediff['new'])

    { project: diff['project'], package: diff['package'], rev: diff['rev'] }
  end

  def diff_label(diff)
    "#{diff['project']} / #{diff['package']} (rev #{diff['rev']})"
  end

  def hidden_review_payload(review)
    capture do
      [:by_user, :by_group, :by_project, :by_package].each do |key|
        concat(hidden_field_tag(key, review[key])) if review[key]
      end
    end
  end

  # rubocop:disable Style/FormatStringToken, Style/FormatString
  def request_action_header(action, creator)
    source_project_hash = { project: action[:sprj], package: action[:spkg] }

    case action[:type]
    when :submit
      'Submit %{source_container} to %{target_container}' % {
        source_container: project_or_package_link(source_project_hash),
        target_container: project_or_package_link(project: action[:tprj], package: action[:tpkg])
      }
    when :delete
      target_repository = "repository #{link_to(action[:trepo], repositories_path(project: action[:tprj], repository: action[:trepo]))} for " if action[:trepo]

      'Delete %{target_repository}%{target_container}' % {
        target_repository: target_repository,
        target_container: project_or_package_link(project: action[:tprj], package: action[:tpkg])
      }
    when :add_role, :set_bugowner
      '%{creator} wants %{requester} to %{task} for %{target_container}' % {
        creator: user_with_realname_and_icon(creator),
        requester: requester_str(creator, action[:user], action[:group]),
        task: creator_intentions(action[:role]),
        target_container: project_or_package_link(project: action[:tprj], package: action[:tpkg])
      }
    when :change_devel
      'Set the devel project to %{source_container} for %{target_container}' % {
        source_container: project_or_package_link(source_project_hash),
        target_container: project_or_package_link(project: action[:tprj], package: action[:tpkg])
      }
    when :maintenance_incident
      source_project_hash.update(homeproject: creator)
      'Submit update from %{source_container} to %{target_container}' % {
        source_container: project_or_package_link(source_project_hash),
        target_container: project_or_package_link(project: action[:tprj], package: action[:tpkg])
      }
    when :maintenance_release
      'Release %{source_container} to %{target_container}' % {
        source_container: project_or_package_link(source_project_hash),
        target_container: project_or_package_link(project: action[:tprj], package: action[:tpkg])
      }
    end.html_safe
  end
  # rubocop:enable Style/FormatStringToken, Style/FormatString

  def review_request_reason(bs_request, review)
    bs_request.request_history_elements.where(description_extension: review[:id]).pluck(:comment).first.presence || 'No reason given'
  end

  def list_maintainers(maintainers)
    maintainers.pluck(:login).map do |maintainer|
      user_with_realname_and_icon(maintainer, short: true)
    end.to_sentence.html_safe
  end
end
