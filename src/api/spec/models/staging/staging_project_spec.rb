require 'rails_helper'
require 'webmock/rspec'

RSpec.describe Staging::StagingProject, vcr: true do
  let(:user) { create(:confirmed_user, login: 'tom') }

  let(:managers_group) { create(:group) }
  let(:other_managers_group) { create(:group) }

  let(:staging_workflow) { create(:staging_workflow_with_staging_projects, project: user.home_project, managers_group: managers_group) }
  let(:staging_project) { staging_workflow.staging_projects.first }

  let!(:repository) { create(:repository, architectures: ['x86_64'], project: staging_project, name: 'staging_repository') }
  let!(:repository_arch) { repository.repository_architectures.first }
  let!(:architecture) { repository_arch.architecture }
  let!(:package) { create(:package_with_file, project: staging_project) }

  let!(:published_report) { create(:status_report, checkable: repository) }
  let!(:build_report) { create(:status_report, checkable: repository_arch) }
  let!(:repository_uuid) { published_report.uuid }
  let!(:build_uuid) { build_report.uuid }

  let(:target_project) { create(:project, name: 'target_project') }
  let(:source_project) { create(:project, :as_submission_source, name: 'source_project') }
  let(:target_package) { create(:package, name: 'target_package', project: target_project) }
  let(:source_package) { create(:package, name: 'source_package', project: source_project) }

  let(:request_attributes) do
    {
      target_project: target_project.name,
      target_package: target_package.name,
      source_project: source_project.name,
      source_package: source_package.name
    }
  end

  let!(:submit_request) { create(:bs_request_with_submit_action, request_attributes.merge(staging_project: staging_project)) }

  before do
    allow(Backend::Api::Published).to receive(:build_id).with(staging_project.name, repository.name).and_return(repository_uuid)
    allow(Backend::Api::Build::Repository).to receive(:build_id).with(staging_project.name, repository.name, architecture.name).and_return(build_uuid)
  end

  describe '#missing_reviews' do
    let(:other_user) { create(:confirmed_user) }
    let(:other_package) { create(:package) }
    let(:group) { create(:group) }
    let!(:review_1) { create(:review, by_user:    other_user,            bs_request: submit_request) }
    let!(:review_2) { create(:review, by_group:   group,                 bs_request: submit_request) }
    let!(:review_3) { create(:review, by_project: other_package.project, bs_request: submit_request) }
    let!(:review_4) { create(:review, by_package: other_package,         by_project: other_package.project, bs_request: submit_request) }

    subject { staging_project.missing_reviews }

    it 'contains all open reviews of staged requests' do
      # rubocop:disable Style/BracesAroundHashParameters
      expect(subject).to contain_exactly(
        { id: review_1.id, request: submit_request.number, state: 'new', package: target_package.name, by: other_user.login },
        { id: review_2.id, request: submit_request.number, state: 'new', package: target_package.name, by: group.title },
        { id: review_3.id, request: submit_request.number, state: 'new', package: target_package.name, by: other_package.project.name },
        { id: review_4.id, request: submit_request.number, state: 'new', package: target_package.name, by: other_package.name }
      )
      # rubocop:enable Style/BracesAroundHashParameters
    end

    context 'when there is an accepted review' do
      before do
        review_2.update(state: 'accepted')
      end

      it { expect(subject.map { |review| review[:id] }).not_to include(review_2.id) }
    end
  end

  describe '#untracked_requests' do
    let!(:request_with_review) do
      create(:bs_request_with_submit_action, request_attributes.merge(review_by_project: staging_project))
    end

    it { expect(staging_project.untracked_requests).to contain_exactly(request_with_review) }
  end

  describe '#overall_state' do
    before do
      User.current = user
    end

    context 'when there are no staged requests' do
      before do
        submit_request.destroy
      end

      it { expect(staging_project.overall_state).to eq(:empty) }
    end

    context 'when request got revoked' do
      before do
        submit_request.update(state: 'revoked')
      end

      it { expect(staging_project.overall_state).to eq(:unacceptable) }
    end

    context 'when there are missing checks on published repo' do
      before do
        repository.update(required_checks: ['check_1'])
      end

      it { expect(staging_project.overall_state).to eq(:testing) }
    end

    context 'when there are missing checks on build repo' do
      before do
        repository_arch.update(required_checks: ['check_1'])
      end

      it { expect(staging_project.overall_state).to eq(:testing) }
    end

    context 'when there are pending checks' do
      let!(:check) { create(:check, name: 'check_1', status_report: published_report, state: 'pending') }

      it { expect(staging_project.overall_state).to eq(:testing) }
    end

    context 'when there are failed checks on published repo' do
      let!(:check) { create(:check, name: 'check_1', status_report: published_report, state: 'failure') }

      it { expect(staging_project.overall_state).to eq(:failed) }
    end

    context 'when there are failed checks on build repo' do
      let!(:check) { create(:check, name: 'check_1', status_report: build_report, state: 'failure') }

      it { expect(staging_project.overall_state).to eq(:failed) }
      it { expect(staging_project.checks).to contain_exactly(check) }
    end

    context 'when there are succeeded checks' do
      let!(:check) { create(:check, name: 'check_1', status_report: published_report, state: 'success') }

      it { expect(staging_project.overall_state).to eq(:acceptable) }
    end

    context 'when we only have outdated checks' do
      let!(:check) { create(:check, name: 'check_1', status_report: published_report, state: 'failure') }

      before do
        repository.update(required_checks: ['check_1'])
        published_report.update(uuid: 'doesnotmatch')
      end

      it { expect(staging_project.overall_state).to eq(:testing) }
      it { expect(staging_project.missing_checks).to contain_exactly('check_1') }
      it { expect(staging_project.checks).to be_empty }
    end
  end

  describe '#assign_managers_group' do
    context 'when the group wasn\'t assigned before' do
      before do
        User.current = user
        staging_project.assign_managers_group(other_managers_group)
        staging_project.store
      end

      it { expect(staging_project.reload.groups).to include(other_managers_group) }
    end

    context 'when the group was already assigned' do
      let(:assign_group) do
        staging_project.assign_managers_group(managers_group)
        staging_project.store
      end

      it { expect { assign_group }.not_to change(Relationship, :count) }
    end
  end

  describe '#unassign_managers_group' do
    before do
      staging_project.unassign_managers_group(managers_group)
      staging_project.store
    end

    it { expect(staging_project.reload.groups).to be_empty }
  end
end
