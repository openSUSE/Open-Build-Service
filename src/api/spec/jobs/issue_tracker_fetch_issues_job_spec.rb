require 'rails_helper'
require 'webmock/rspec'

RSpec.describe IssueTrackerFetchIssuesJob, type: :job, vcr: true do
  include ActiveJob::TestHelper

  describe '#perform' do
    let!(:issue_tracker) { double(:issue_tracker, id: 1) }

    before do
      allow(IssueTracker).to receive(:find).and_return(issue_tracker)
      allow(issue_tracker).to receive(:fetch_issues)
    end

    subject! { IssueTrackerFetchIssuesJob.new.perform(issue_tracker.id) }

    it 'fetches the issues' do
      expect(issue_tracker).to have_received(:fetch_issues)
    end
  end
end
