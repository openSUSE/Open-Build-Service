require 'rails_helper'

RSpec.describe TriggerController, vcr: true do
  let(:admin) { create(:admin_user, :with_home, login: 'foo_admin') }
  let(:project) { admin.home_project }
  let(:package) { create(:package, name: 'package_trigger', project: project) }
  let(:repository) { create(:repository, name: 'package_test_repository', architectures: ['x86_64'], project: project) }
  let(:target_project) { create(:project, name: 'target_project') }
  let(:target_repository) { create(:repository, name: 'target_repository', project: target_project) }
  let(:release_target) { create(:release_target, target_repository: target_repository, repository: repository, trigger: 'manual') }

  render_views

  before do
    allow(User).to receive(:session!).and_return(admin)
    allow(::TriggerControllerService::TokenExtractor).to receive(:new) {
      -> { OpenStruct.new(valid?: true, token: token) }
    }
    package
  end

  describe '#rebuild' do
    context 'authentication token is invalid' do
      before do
        allow(::TriggerControllerService::TokenExtractor).to receive(:new) {
          -> { OpenStruct.new(valid?: false, token: nil) }
        }
        post :rebuild, params: { format: :xml }
      end

      it { expect(response).to have_http_status(:forbidden) }
    end

    context 'when token is valid and packet rebuild' do
      let(:token) { Token::Rebuild.create(user: admin, package: package) }

      before do
        allow(Backend::Api::Sources::Package).to receive(:rebuild).and_return("<status code=\"ok\" />\n")
        post :rebuild, params: { format: :xml }
      end

      it { expect(response).to have_http_status(:success) }
    end
  end

  describe '#release' do
    context 'for inexistent project' do
      before do
        post :release, params: { project: 'foo', format: :xml }
      end

      it { expect(response).to have_http_status(:forbidden) }
    end

    context 'when token is valid and package exists' do
      let(:token) { Token::Release.create(user: admin, package: package) }

      let(:backend_url) do
        "/build/#{target_project.name}/#{target_repository.name}/x86_64/#{package.name}" \
          "?cmd=copy&oproject=#{CGI.escape(project.name)}&opackage=#{package.name}&orepository=#{repository.name}" \
          '&resign=1&multibuild=1'
      end

      before do
        release_target
        allow(Backend::Connection).to receive(:post).and_call_original
        allow(Backend::Connection).to receive(:post).with(backend_url).and_return("<status code=\"ok\" />\n")
        post :release, params: { package: package, format: :xml }
      end

      it { expect(response).to have_http_status(:success) }
    end

    context 'when user has no rights for source' do
      let(:user) { create(:confirmed_user, login: 'mrfluffy') }
      let(:token) { Token::Release.create(user: user, package: package) }
      before do
        allow(User).to receive(:session!).and_return(user)
        allow(::TriggerControllerService::TokenExtractor).to receive(:new) {
          -> { OpenStruct.new(valid?: true, token: token) }
        }
      end

      it { expect { post :release, params: { package: package, format: :xml } }.to raise_error.with_message(/no permission for package/) }
    end

    context 'when user has no rights for target' do
      let(:user) { create(:confirmed_user, login: 'mrfluffy') }
      let(:token) { Token::Release.create(user: user, package: package) }
      let!(:relationship_package_user) { create(:relationship_package_user, user: user, package: package) }

      before do
        release_target
        allow(User).to receive(:session!).and_return(user)
        allow(User).to receive(:possibly_nobody).and_return(user)
        allow(::TriggerControllerService::TokenExtractor).to receive(:new) {
          -> { OpenStruct.new(valid?: true, token: token) }
        }
        post :release, params: { package: package, format: :xml }
      end

      it { expect(response).to have_http_status(403) }
      it { expect(response.body).to include("No permission to modify project 'target_project' for user 'mrfluffy'") }
    end

    context 'when there are no release targets' do
      let(:user) { create(:confirmed_user, login: 'mrfluffy') }
      let(:token) { Token::Release.create(user: user, package: package) }
      let!(:relationship_package_user) { create(:relationship_package_user, user: user, package: package) }

      before do
        allow(User).to receive(:session!).and_return(user)
        allow(User).to receive(:possibly_nobody).and_return(user)
        allow(::TriggerControllerService::TokenExtractor).to receive(:new) {
          -> { OpenStruct.new(valid?: true, token: token) }
        }
      end

      it { expect { post :release, params: { package: package, format: :xml } }.to raise_error.with_message(/has no release targets that are triggered manually/) }
    end
  end

  describe '#runservice' do
    let(:token) { Token::Service.create(user: admin, package: package) }
    let(:project) { admin.home_project }
    let!(:package) { create(:package_with_service, name: 'package_with_service', project: project) }

    before do
      post :runservice, params: { package: package, format: :xml }
    end

    it { expect(response).to have_http_status(:success) }
  end
end
