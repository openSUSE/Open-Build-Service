require 'rails_helper'

RSpec.describe Token::Workflow do
  describe '#call' do
    let(:token_user) { create(:confirmed_user, :with_home, login: 'Iggy') }
    let(:workflow_token) { create(:workflow_token, user: token_user) }
    let(:workflow_run) { create(:workflow_run, token: workflow_token) }

    context 'without a payload' do
      it do
        expect { workflow_token.call({ workflow_run: workflow_run }) }.to raise_error(Token::Errors::MissingPayload, 'A payload is required').and(change(workflow_token, :triggered_at))
      end
    end

    context 'without validation errors' do
      let(:scm) { 'github' }
      let(:event) { 'pull_request' }
      let(:github_payload) do
        {
          action: 'opened',
          pull_request: {
            head: {
              ref: 'my_branch',
              repo: { full_name: 'username/test_repo' },
              sha: '12345678'
            },
            base: {
              ref: 'main',
              repo: { full_name: 'openSUSE/open-build-service' }
            }
          },
          number: '4',
          sender: { url: 'https://api.github.com' }
        }
      end
      let(:github_extractor_payload) do
        {
          scm: 'github',
          event: 'pull_request',
          api_endpoint: 'https://api.github.com',
          commit_sha: '12345678',
          pr_number: '4',
          source_branch: 'my_branch',
          target_branch: 'main',
          action: 'opened',
          source_repository_full_name: 'username/test_repo',
          target_repository_full_name: 'openSUSE/open-build-service'
        }
      end
      let(:scm_extractor) { TriggerControllerService::ScmExtractor.new(scm, event, github_payload) }
      let(:scm_webhook) { ScmWebhook.new(payload: github_extractor_payload) }
      let(:yaml_downloader) { Workflows::YAMLDownloader.new(scm_webhook.payload, token: workflow_token) }
      let(:yaml_file) { File.expand_path(Rails.root.join('spec/support/files/workflows.yml')) }
      let(:yaml_to_workflows_service) { Workflows::YAMLToWorkflowsService.new(yaml_file: yaml_file, scm_webhook: scm_webhook, token: workflow_token) }
      let(:workflow) do
        Workflow.new(scm_webhook: scm_webhook, token: workflow_token,
                     workflow_instructions: { steps: [branch_package: { source_project: 'home:Admin', source_package: 'ctris', target_project: 'dev:tools' }] })
      end
      let(:workflows) { [workflow] }

      before do
        # Skipping call since it's tested in the Workflow model
        allow(workflow).to receive(:call).and_return(true)

        allow(TriggerControllerService::ScmExtractor).to receive(:new).with(scm, event, github_payload).and_return(scm_extractor)
        allow(scm_extractor).to receive(:call).and_return(scm_webhook)
        allow(Workflows::YAMLDownloader).to receive(:new).with(scm_webhook.payload, token: workflow_token).and_return(yaml_downloader)
        allow(yaml_downloader).to receive(:call).and_return(yaml_file)
        allow(Workflows::YAMLToWorkflowsService).to receive(:new).with(yaml_file: yaml_file, scm_webhook: scm_webhook, token: workflow_token).and_return(yaml_to_workflows_service)
        allow(yaml_to_workflows_service).to receive(:call).and_return(workflows)
      end

      subject { workflow_token.call(scm: scm, event: event, payload: github_payload, workflow_run: workflow_run) }

      it 'returns no validation errors' do
        expect(subject).to eq([])
      end

      it { expect { subject }.to change(workflow_token, :triggered_at) & change(workflow_run, :response_url).to('https://api.github.com') }
    end

    context 'with validation errors' do
      let(:scm) { 'github' }
      let(:event) { 'wrong_event' }
      let(:github_payload) do
        {
          action: 'opened',
          pull_request: {
            head: {
              ref: 'my_branch',
              repo: { full_name: 'username/test_repo' },
              sha: '12345678'
            },
            base: {
              ref: 'main',
              repo: { full_name: 'openSUSE/open-build-service' }
            }
          },
          number: '4',
          sender: { url: 'https://api.github.com' }
        }
      end
      let(:github_extractor_payload) do
        {
          scm: 'github',
          event: event,
          api_endpoint: 'https://api.github.com'
        }
      end
      let(:scm_extractor) { TriggerControllerService::ScmExtractor.new(scm, event, github_payload) }
      let(:scm_webhook) { ScmWebhook.new(payload: github_extractor_payload) }
      let(:yaml_downloader) { Workflows::YAMLDownloader.new(scm_webhook.payload, token: workflow_token) }
      let(:yaml_file) { File.expand_path(Rails.root.join('spec/support/files/workflows.yml')) }
      let(:yaml_to_workflows_service) { Workflows::YAMLToWorkflowsService.new(yaml_file: yaml_file, scm_webhook: scm_webhook, token: workflow_token) }
      let(:workflows) { [Workflow.new(scm_webhook: scm_webhook, token: workflow_token, workflow_instructions: {})] }

      before do
        allow(TriggerControllerService::ScmExtractor).to receive(:new).with(scm, event, github_payload).and_return(scm_extractor)
        allow(scm_extractor).to receive(:call).and_return(scm_webhook)
        allow(Workflows::YAMLDownloader).to receive(:new).with(scm_webhook.payload, token: workflow_token).and_return(yaml_downloader)
        allow(yaml_downloader).to receive(:call).and_return(yaml_file)
        allow(Workflows::YAMLToWorkflowsService).to receive(:new).with(yaml_file: yaml_file, scm_webhook: scm_webhook, token: workflow_token).and_return(yaml_to_workflows_service)
        allow(yaml_to_workflows_service).to receive(:call).and_return(workflows)
      end

      subject { workflow_token.call(scm: scm, event: event, payload: github_payload, workflow_run: workflow_run) }

      it 'returns the validation errors' do
        expect(subject).to eq(['Event not supported.', 'Workflow steps are not present'])
      end

      it { expect { subject }.to change(workflow_token, :triggered_at) & change(workflow_run, :response_url).to('https://api.github.com') }
    end
  end
end
