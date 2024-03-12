module Workflows
  class ArtifactsCollector
    def initialize(step:, workflow_run_id:)
      @step = step
      @workflow_run_id = workflow_run_id
    end

    def call
      artifacts = case @step.class.name
                  when 'Workflow::Step::BranchPackageStep', 'Workflow::Step::LinkPackageStep'
                    {
                      source_project: @step.step_instructions[:source_project],
                      source_package: @step.step_instructions[:source_package],
                      target_project: @step.send(:target_project_name),
                      target_package: @step.send(:target_package_name)
                    }
                  when 'Workflow::Step::RebuildPackage', 'Workflow::Step::TriggerServices', 'Workflow::Step::SetFlags'
                    @step.step_instructions
                  when 'Workflow::Step::ConfigureRepositories'
                    {
                      project: @step.send(:target_project_name),
                      repositories: @step.step_instructions[:repositories]
                    }
                  when 'Workflow::Step::SubmitRequest'
                    {
                      request_numbers_and_state: @step.artifact
                    }
                  end
      WorkflowArtifactsPerStep.find_or_create_by(workflow_run_id: @workflow_run_id, step: @step.class.name, artifacts: artifacts.to_json) if artifacts
    end
  end
end
