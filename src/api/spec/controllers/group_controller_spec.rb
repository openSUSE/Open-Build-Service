require 'rails_helper'

RSpec.describe GroupController, vcr: false do
  let(:admin_user) { create(:admin_user) }

  before do
    login admin_user
  end

  describe 'DELETE #delete' do
    before do
      delete :delete, params: { title: group.title, format: :xml }
    end

    shared_examples 'successful group deletion' do
      it 'responds with 200 OK' do
        expect(response.code).to eq('200')
      end

      it 'deletes the record' do
        expect(Group.find_by(id: group.id)).to be_nil
        expect(GroupsUser.where(group_id: group.id)).not_to exist
      end
    end

    context 'group without users' do
      let(:group) { create(:group) }

      it_behaves_like 'successful group deletion'
    end

    context 'group with users' do
      let(:group) { create(:group_with_user) }

      it_behaves_like 'successful group deletion'
    end
  end
end
