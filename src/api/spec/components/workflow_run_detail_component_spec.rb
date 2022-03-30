require 'rails_helper'

RSpec.describe WorkflowRunDetailComponent, type: :component do
  let(:workflow_token) { create(:workflow_token) }
  let(:request_headers) do
    <<~END_OF_HEADERS
      HTTP_X_GITHUB_EVENT: pull_request
    END_OF_HEADERS
  end
  let(:request_payload) do
    <<-END_OF_PAYLOAD
    {
      "foo": "bar"
    }
    END_OF_PAYLOAD
  end
  let(:workflow_run) do
    create(:workflow_run,
           token: workflow_token,
           request_headers: request_headers,
           request_json_payload: request_payload)
  end

  before do
    render_inline(described_class.new(workflow_run: workflow_run))
  end

  context 'every single workflow run' do
    it { expect(rendered_component).to have_text('Request') }
    it { expect(rendered_component).to have_text('Response') }
    it { expect(rendered_component).to have_text('pull_request') }
    it { expect(rendered_component).to have_text('foo') }
  end

  context 'when the payload cannot be parsed' do
    let(:request_payload) { 'Unparseable payload' }

    it 'shows nothing on the payload tab' do
      expect(rendered_component).to have_text('Unparseable payload')
    end
  end
end
