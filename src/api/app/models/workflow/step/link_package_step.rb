class Workflow::Step::LinkPackageStep < Workflow::Step
  include ScmSyncEnabledStep
  include TargetProjectLifeCycleSupport

  REQUIRED_KEYS = %i[source_project source_package target_project].freeze

  validate :validate_source_project_or_package_are_not_scmsynced

  def call
    return unless valid?

    if scm_webhook.closed_merged_pull_request?
      destroy_target_project
    elsif scm_webhook.reopened_pull_request?
      restore_target_project
    elsif scm_webhook.new_commit_event?
      create_target_package
      create_link
      Workflows::ScmEventSubscriptionCreator.new(token, workflow_run, scm_webhook, target_package).call

      target_package
    end
  end

  private

  def target_project_base_name
    step_instructions[:target_project]
  end

  def target_project
    Project.find_by(name: target_project_name)
  end

  def create_target_package
    return if target_package.present?

    check_source_access

    if target_project.nil?
      project = Project.new(name: target_project_name)
      Pundit.authorize(@token.executor, project, :create?)

      project.save!
      project.commit_user = User.session
      project.relationships.create!(user: User.session, role: Role.find_by_title('maintainer'))
      project.store
    end

    Pundit.authorize(@token.executor, target_project, :update?)
    target_project.packages.create(name: target_package_name)
  end

  # Will raise an exception if the source package is not accesible
  def check_source_access
    # if we branch from remote there is no need to check access. Either the package exists or not...
    return if Project.find_remote_project(step_instructions[:source_project]).present?

    Package.get_by_project_and_name(step_instructions[:source_project], step_instructions[:source_package])
  end

  def create_link
    Backend::Api::Sources::Package.write_link(target_project_name,
                                              target_package_name,
                                              @token.executor,
                                              link_xml(project: step_instructions[:source_project],
                                                       package: step_instructions[:source_package]))
  end

  def link_xml(opts = {})
    # "<link package=\"foo\" project=\"bar\" />"
    Nokogiri::XML::Builder.new { |x| x.link(opts) }.doc.root.to_s
  end

  def validate_source_project_or_package_are_not_scmsynced
    if scm_synced_project?
      errors.add(:base,
                 "project '#{step_instructions[:source_project]}' is developed in SCM. Branch it instead.")
    end
    return unless scm_synced_package?

    errors.add(:base,
               "package '#{step_instructions[:source_package]}' is developed in SCM. Branch it instead.")
  end
end
