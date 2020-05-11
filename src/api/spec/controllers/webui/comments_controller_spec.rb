require 'rails_helper'

RSpec.describe Webui::CommentsController, type: :controller do
  let(:user) { create(:confirmed_user, login: 'luck') }

  before do
    login user
  end

  describe 'POST #create' do
    let(:project) { create(:project) }
    let(:package) { create(:package, project: project) }
    let(:bs_request) { create(:set_bugowner_request) }

    context 'with invalid commentable_type' do
      let(:comment_params) do
        { comment: { body: 'This is AWESOME!' }, commentable_type: 'FOOBAR', commentable_id: 31_337 }
      end

      subject { post :create, params: comment_params }

      it { expect(subject.request.flash[:success]).to be_nil }
      it { expect(subject.request.flash[:error]).not_to(be_nil) }
      it { expect(subject).to redirect_to(root_path) }
    end

    context 'with a valid comment' do
      RSpec.shared_examples 'saving a comment' do
        before do
          params = { comment: { body: "This #{commentable.model_name.singular} is AWESOME!" },
                     commentable_type: commentable.class, commentable_id: commentable.id }
          post :create, params: params
        end

        it { expect(flash[:success]).to eq('Comment created successfully.') }
        it { expect(commentable.comments.first.body).to eq("This #{commentable.model_name.singular} is AWESOME!") }
      end

      context 'of a project' do
        let(:commentable) { project }
        include_examples 'saving a comment'
      end

      context 'of a package' do
        let(:commentable) { package }
        include_examples 'saving a comment'
      end

      context 'of a bs_request' do
        let(:commentable) { bs_request }
        include_examples 'saving a comment'
      end
    end

    context 'saving a comment without body' do
      before do
        params = { comment: { body: '' }, commentable_type: package.class, commentable_id: package.id }
        post :create, params: params
      end

      it { expect(flash[:error]).to eq("Failed to create comment: Body can't be blank.") }
      it { expect(package.comments.count).to eq(0) }
    end

    context "does not allow to overwrite the comment's user" do
      it 'should not created' do
        params = { comment: { body: 'This project is AWESOME!', user_id: user }, commentable_type: project.class, commentable_id: project.id }
        expect { post :create, params: params }.to raise_error(ActionController::UnpermittedParameters)
      end
    end
  end

  describe 'DELETE #destroy' do
    let(:admin) { create(:admin_user, login: 'Admin') }
    let(:comment) { create(:comment_project, user: user) }
    let(:other_comment) { create(:comment_project) }

    context 'can destroy own comments' do
      before do
        delete :destroy, params: { id: comment.id }
      end

      it { expect(flash[:success]).to eq('Comment deleted successfully.') }
      it { expect(Comment.where(id: comment.id)).to eq([]) }
    end

    context 'cannot destroy comment of somebody else' do
      before do
        delete :destroy, params: { id: other_comment.id }
      end

      it { expect(flash[:success]).to eq(nil) }
      it { expect(Comment.where(id: comment.id)).to eq([comment]) }
    end

    context 'admin can destroy comments not owned by him' do
      before do
        login admin
        delete :destroy, params: { id: other_comment.id }
      end

      it { expect(flash[:success]).to eq('Comment deleted successfully.') }
      it { expect(Comment.where(id: other_comment.id)).to eq([]) }
    end
  end
end
