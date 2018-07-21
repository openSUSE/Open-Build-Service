require 'rails_helper'
require 'webmock/rspec'

RSpec.describe Webui::ObsFactory::StagingProjectsController, type: :controller do
  let(:factory) { create(:project, name: 'openSUSE:Factory') }
  let!(:factory_staging_a) { create(:project, name: 'openSUSE:Factory:Staging:A', description: 'Factory staging project A') }

  describe 'GET #index' do
    let!(:factory_staging) { create(:project, name: 'openSUSE:Factory:Staging') }

    context 'without dashboard package' do
      before do
        get :index, params: { project: factory }
      end

      it { expect(response).to have_http_status(:success) }
      it { expect(response).to render_template(:index) }
      it { expect(assigns(:backlog_requests_ignored)).to be_empty }
      it { expect(assigns(:backlog_requests)).to be_empty }
      it { expect(assigns(:requests_state_new)).to be_empty }
      it { expect(assigns(:project)).to eq(factory) }
    end

    context 'with dashboard package' do
      let!(:dashboard) { create(:package, name: 'dashboard', project: factory_staging) }

      context 'with ignored_requests file' do
        let(:backend_url) { "#{CONFIG['source_url']}/source/#{factory_staging}/#{dashboard}/ignored_requests" }

        context 'with content' do
          let(:target_package) { create(:package, name: 'target_package', project: factory) }
          let(:source_project) { create(:project, name: 'source_project') }
          let(:source_package) { create(:package, name: 'source_package', project: source_project) }
          let(:group) { create(:group, title: 'factory-staging') }
          let!(:create_review_requests) do
            [613_048, 99_999].map do |number|
              ObsFactory::Request.new(create(:review_bs_request_by_group,
                                             number: number,
                                             reviewer: group.title,
                                             target_project: factory.name,
                                             target_package: target_package.name,
                                             source_project: source_package.project.name,
                                             source_package: source_package.name))
            end
          end
          let!(:create_review_requests_in_state_new) do
            [617_649, 111_111].map do |number|
              ObsFactory::Request.new(create(:review_bs_request_by_group,
                                             number: number,
                                             reviewer: group.title,
                                             request_state: 'new',
                                             target_project: factory.name,
                                             target_package: target_package.name,
                                             source_project: source_package.project.name,
                                             source_package: source_package.name))
            end
          end
          let(:backend_response) do
            <<~TEXT
              613048: Needs to come in sync with Mesa changes (libwayland-egl1 is also built by Mesa.spec)
              617649: Needs a perl fix - https://rt.perl.org/Public/Bug/Display.html?id=133295
            TEXT
          end

          before do
            allow_any_instance_of(Package).to receive(:file_exists?).with('ignored_requests').and_return(true)
            stub_request(:get, backend_url).and_return(body: backend_response)

            get :index, params: { project: factory }
          end

          it { expect(response).to have_http_status(:success) }
          it { expect(response).to render_template(:index) }
          it { expect(assigns(:backlog_requests_ignored)).to contain_exactly(create_review_requests.first) }
          it { expect(assigns(:backlog_requests)).to contain_exactly(create_review_requests.last) }
          it { expect(assigns(:requests_state_new)).to contain_exactly(create_review_requests_in_state_new.last) }
          it { expect(assigns(:project)).to eq(factory) }
        end

        context 'without content' do
          before do
            allow_any_instance_of(Package).to receive(:file_exists?).with('ignored_requests').and_return(true)

            stub_request(:get, backend_url).and_return(body: '')
            get :index, params: { project: factory }
          end

          it { expect(response).to have_http_status(:success) }
          it { expect(response).to render_template(:index) }
          it { expect(assigns(:backlog_requests_ignored)).to be_empty }
          it { expect(assigns(:backlog_requests)).to be_empty }
          it { expect(assigns(:requests_state_new)).to be_empty }
          it { expect(assigns(:project)).to eq(factory) }
        end
      end
    end
  end

  describe 'GET #show' do
    context 'with a existent factory_staging_project' do
      subject { get :show, params: { project: factory, project_name: 'A' } }

      it { expect(subject).to have_http_status(:success) }
      it { expect(subject).to render_template(:show) }
    end

    context 'with a non-existent factory_staging_project' do
      subject { get :show, params: { project: factory, project_name: 'B' } }

      it { expect(subject).to have_http_status(:found) }
      it { expect(subject).to redirect_to(root_path) }
    end
  end
end
