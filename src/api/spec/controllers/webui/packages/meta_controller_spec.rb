require 'rails_helper'

RSpec.describe Webui::Packages::MetaController, vcr: true do
  let(:user) { create(:confirmed_user, login: 'tom') }
  let(:source_project) { user.home_project }
  let(:source_package) { create(:package, name: 'my_package', project: source_project) }

  describe 'GET #meta' do
    before do
      login user
      get :show, params: { project: source_project, package: source_package }
    end

    it { expect(response).to render_template('webui/packages/meta/show') }
    it { expect(response).to have_http_status(:success) }
  end

  describe 'PUT #update' do
    let(:valid_meta) do
      "<package name=\"#{source_package.name}\" project=\"#{source_project.name}\">" \
        '<title>My Test package Updated via Webui</title><description/></package>'
    end

    let(:invalid_meta_because_package_name) do
      "<package name=\"whatever\" project=\"#{source_project.name}\">" \
        '<title>Invalid meta PACKAGE NAME</title><description/></package>'
    end

    let(:invalid_meta_because_project_name) do
      "<package name=\"#{source_package.name}\" project=\"whatever\">" \
        '<title>Invalid meta PROJECT NAME</title><description/></package>'
    end

    let(:invalid_meta_because_xml) do
      "<package name=\"#{source_package.name}\" project=\"#{source_project.name}\">" \
        '<title>Invalid meta WRONG XML</title><description/></paaaaackage>'
    end

    before do
      login user
    end

    context 'with proper params' do
      before do
        put :update, params: { project: source_project, package: source_package, meta: valid_meta }
      end

      it { expect(flash[:success]).to eq('The Meta file has been successfully saved.') }
      it { expect(response).to have_http_status(:ok) }
    end

    context 'without admin rights to raise protection level' do
      before do
        allow_any_instance_of(Package).to receive(:disabled_for?).with('sourceaccess', nil, nil).and_return(false)
        allow(FlagHelper).to receive(:xml_disabled_for?).with(Xmlhash.parse(valid_meta), 'sourceaccess').and_return(true)

        put :update, params: { project: source_project, package: source_package, meta: valid_meta }
      end

      it { expect(flash[:error]).to eq('Error while saving the Meta file: admin rights are required to raise the protection level of a package.') }
      it { expect(response).to have_http_status(:bad_request) }
    end

    context 'with an invalid package name' do
      before do
        put :update, params: { project: source_project, package: source_package, meta: invalid_meta_because_package_name }
      end

      it { expect(flash[:error]).to eq('Error while saving the Meta file: package name in xml data does not match resource path component.') }
      it { expect(response).to have_http_status(:bad_request) }
    end

    context 'with an invalid project name' do
      before do
        put :update, params: { project: source_project, package: source_package, meta: invalid_meta_because_project_name }
      end

      it { expect(flash[:error]).to eq('Error while saving the Meta file: project name in xml data does not match resource path component.') }
      it { expect(response).to have_http_status(:bad_request) }
    end

    context 'with invalid XML' do
      before do
        put :update, params: { project: source_project, package: source_package, meta: invalid_meta_because_xml }
      end

      it { expect(flash[:error]).to match(/package validation error: .*: FATAL: Opening and ending tag mismatch: .*/) }
      it { expect(response).to have_http_status(:bad_request) }
    end

    context 'with an unexistent package' do
      before do
        put :update, params: { project: source_project, package: 'blah', meta: valid_meta }
      end

      it { expect(flash[:error]).to eq("Package \"blah\" not found in project \"#{source_project.name}\"") }
      it { expect(response).to redirect_to(project_show_path(project: source_project, nextstatus: 404)) }
    end

    context 'when connection with the backend fails' do
      before do
        allow_any_instance_of(Package).to receive(:update_from_xml).and_raise(Backend::Error, 'fake message')

        put :update, params: { project: source_project, package: source_package, meta: valid_meta }
      end

      it { expect(flash[:error]).to eq('Error while saving the Meta file: fake message.') }
      it { expect(response).to have_http_status(:bad_request) }
    end

    context 'when not found the User or Group' do
      before do
        allow_any_instance_of(Package).to receive(:update_from_xml).and_raise(NotFoundError, 'fake message')

        put :update, params: { project: source_project, package: source_package, meta: valid_meta }
      end

      it { expect(flash[:error]).to eq('Error while saving the Meta file: fake message.') }
      it { expect(response).to have_http_status(:bad_request) }
    end
  end
end
