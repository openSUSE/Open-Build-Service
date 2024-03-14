RSpec.describe WorkflowRunsFinder do
  subject { described_class.new }

  let(:workflow_token) { create(:workflow_token) }
  # GitHub
  let!(:workflow_run_github_push) do
    create(:workflow_run, :push, :succeeded, token: workflow_token, event_source_name: '94561cd')
  end
  let!(:workflow_run_github_tag_push) do
    create(:workflow_run, :tag_push, :succeeded, token: workflow_token, event_source_name: '94561cd')
  end
  let!(:workflow_run_github_pull_request_opened) { create(:workflow_run, :succeeded, token: workflow_token) }
  let!(:workflow_run_github_pull_request_closed) do
    create(:workflow_run, :succeeded, :pull_request_closed, token: workflow_token)
  end
  # GitLab
  let!(:workflow_run_gitlab_push) do
    create(:workflow_run_gitlab, :push, :succeeded, token: workflow_token, event_source_name: '97561db')
  end
  let!(:workflow_run_gitlab_tag_push) do
    create(:workflow_run_gitlab, :tag_push, :succeeded, token: workflow_token, event_source_name: '97561db')
  end
  let!(:workflow_run_gitlab_pull_request_opened) { create(:workflow_run_gitlab, :succeeded, token: workflow_token) }
  let!(:workflow_run_gitlab_pull_request_closed) do
    create(:workflow_run_gitlab, :succeeded, :pull_request_closed, token: workflow_token)
  end

  before do
    %w[success running fail].each do |status|
      create(:workflow_run, token: workflow_token, status: status,
                            request_headers: "HTTP_X_GITHUB_EVENT: pull_request\n")
    end
  end

  describe '#all' do
    it 'returns all workflow runs' do
      expect(subject.all.count).to eq(11)
    end
  end

  describe '#group_by_generic_event_type' do
    it 'returns a hash with the amount of workflow runs grouped by event' do
      expect(subject.group_by_generic_event_type).to include({ 'pull_request' => 7, 'push' => 2, 'tag_push' => 2 })
    end
  end

  describe '#with_generic_event_type' do
    it 'returns workflows for pull_request generic event' do
      expect(subject.with_generic_event_type('pull_request').count).to eq(7)
    end

    it 'returns workflows for push generic event' do
      expect(subject.with_generic_event_type('push').count).to eq(2)
    end

    it 'returns workflows for tag push generic event' do
      expect(subject.with_generic_event_type('tag_push').count).to eq(2)
    end
  end

  describe '#with_event_source_name' do
    it 'returns workflows for the specfied commit sha' do
      expect(subject.with_event_source_name('97561db', 'commit').count).to eq(2)
    end

    it 'returns all workflow runs when given an empty string' do
      expect(subject.with_event_source_name('', 'commit').count).to eq(11)
    end
  end

  describe '#succeeded' do
    it 'returns all workflow runs with status success' do
      expect(subject.succeeded.count).to eq(9)
    end
  end

  describe '#running' do
    it 'returns all workflow runs with status running' do
      expect(subject.running.count).to eq(1)
    end
  end

  describe '#failed' do
    it 'returns all workflow runs with status fail' do
      expect(subject.failed.count).to eq(1)
    end
  end
end
