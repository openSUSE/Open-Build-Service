require 'rails_helper'

RSpec.describe BranchPackage, vcr: true do
  let(:user) { create(:confirmed_user, login: 'tom') }
  let(:home_project) { user.home_project }
  let!(:project) { create(:project, name: 'BaseDistro') }
  let!(:package) { create(:package, name: 'test_package', project: project) }

  context '#branch' do
    let(:branch_package) { BranchPackage.new(project: project.name, package: package.name) }
    let!(:update_project) { create(:project, name: 'BaseDistro:Update') }
    let(:update_attrib_type) { AttribType.find_by_namespace_and_name!('OBS', 'UpdateProject') }
    let(:attrib_value) { build(:attrib_value, value: 'BaseDistro:Update') }
    let!(:update_attrib) { create(:attrib, project: project, attrib_type: update_attrib_type, values: [attrib_value]) }

    before(:each) do
      User.current = user
    end

    after(:each) do
      Project.where('name LIKE ?', "#{user.home_project}:branches:%").destroy_all
    end

    context 'package with UpdateProject attribute' do
      it 'should increase Package by one' do
        expect { branch_package.branch }.to change{ Package.count }.by(1)
      end

      it 'should create home:tom:branches:BaseDistro:Update project' do
        branch_package.branch
        expect(Project.where(name: "#{home_project.name}:branches:BaseDistro:Update")).to exist
      end
    end
  end
end
