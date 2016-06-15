require 'rails_helper'

RSpec.describe Webui::UserController do
  let!(:user) { create(:confirmed_user, login: "tom") }
  let!(:non_admin_user) { create(:confirmed_user, login: "moi") }
  let!(:admin_user) { create(:admin_user, login: "king") }
  let(:deleted_user) { create(:deleted_user) }

  it { is_expected.to use_before_action(:require_login) }
  it { is_expected.to use_before_action(:require_admin) }

  describe "GET #index" do
    before do
      login admin_user
      get :index
    end

    it { is_expected.to render_template("webui/user/index") }
  end

  describe "GET #show" do
    shared_examples "a non existent account" do
      before do
        request.env["HTTP_REFERER"] = root_url # Needed for the redirect_to :back
        get :show, {user: user}
      end

      it { expect(controller).to set_flash[:error].to("User not found #{user}") }
      it { expect(response).to redirect_to :back }
    end

    context "when the current user is admin" do
      before { login admin_user }

      it "deleted users are shown" do
        get :show, { user: deleted_user }
        expect(response).to render_template("webui/user/show")
      end

      describe "showing a non valid users" do
        subject(:user) { 'INVALID_USER' }
        it_should_behave_like "a non existent account"
      end
    end

    context "when the current user isn't admin" do
      before { login non_admin_user }

      describe "showing a deleted user" do
        subject(:user) { deleted_user }
        it_should_behave_like "a non existent account"
      end

      describe "showing a non valid users" do
        subject(:user) { 'INVALID_USER' }
        it_should_behave_like "a non existent account"
      end
    end
  end

  describe "GET #user_edit" do
    before do
      login admin_user
      get :edit, {user: user}
    end

    it { is_expected.to render_template("webui/user/edit") }
  end

  describe "POST #do_login" do
    before do
      request.env["HTTP_REFERER"] = search_url # Needed for the redirect_to :back
      post :do_login, {username: user.login, password: 'buildservice'}
    end

    it { expect(response).to redirect_to search_url }
  end

  describe "GET #home" do
    skip
  end

  describe "GET #requests" do
    skip
  end

  describe "POST #save" do
    context "when user is updating its own profile" do
      before do
        login user
        post :save, {user: user, realname: 'another real name', email: 'new_valid@email.es' }
        user.reload
      end

      it { expect(user.realname).to eq('another real name') }
      it { expect(user.email).to eq('new_valid@email.es') }
      it { is_expected.to redirect_to user_show_path(user) }
    end

    context "when user is trying to update another user's profile" do
      before do
        login user
        request.env["HTTP_REFERER"] = root_url # Needed for the redirect_to :back
        post :save, {user: non_admin_user, realname: 'another real name', email: 'new_valid@email.es' }
        non_admin_user.reload
      end

      it { expect(non_admin_user.realname).not_to eq('another real name') }
      it { expect(non_admin_user.email).not_to eq('new_valid@email.es') }
      it { expect(flash[:error]).to eq("Can't edit #{non_admin_user.login}") }
      it { is_expected.to redirect_to :back }
    end

    context "when admin is updating another user's profile" do
      before do
        login admin_user
        post :save, {user: user, realname: 'another real name', email: 'new_valid@email.es' }
        user.reload
      end

      it { expect(user.realname).to eq('another real name') }
      it { expect(user.email).to eq('new_valid@email.es') }
      it { is_expected.to redirect_to user_show_path(user) }
    end
  end

  describe "GET #delete" do
    skip
  end

  describe "GET #confirm" do
    skip
  end

  describe "GET #lock" do
    skip
  end

  describe "GET #admin" do
    skip
  end

  describe "GET #save_dialog" do
    skip
  end

  describe "GET #user_icon" do
    skip
  end

  describe "GET #icon" do
    skip
  end

  describe "POST #register" do
    let!(:new_user) { build(:user, login: 'moi_new') }

    context "when existing user is already registered with this login" do
      before do
        already_registered_user = create(:confirmed_user, login: 'previous_user')
        post :register, { login: already_registered_user.login, email: already_registered_user.email, password: 'buildservice' }
      end

      it { expect(flash[:error]).not_to be nil }
      it { expect(response).to redirect_to root_path }
    end

    context "when home project creation enabled" do
      before do
        Configuration.stubs(:allow_user_to_create_home_project).returns(true)
        post :register, { login: new_user.login, email: new_user.email, password: 'buildservice' }
      end

      it { expect(flash[:success]).to eq("The account '#{new_user.login}' is now active.") }
      it { expect(response).to redirect_to project_show_path(new_user.home_project_name) }
    end

    context "when home project creation disabled" do
      before do
        Configuration.stubs(:allow_user_to_create_home_project).returns(false)
        post :register, { login: new_user.login, email: new_user.email, password: 'buildservice' }
      end

      it { expect(flash[:success]).to eq("The account '#{new_user.login}' is now active.") }
      it { expect(response).to redirect_to root_path }
    end
  end

  describe "GET #register_user" do
    skip
  end

  describe "GET #password_dialog" do
    skip
  end

  describe "GET #change_password" do
    skip
  end

  describe "GET #autocomplete" do
    skip
  end

  describe "GET #tokens" do
    skip
  end

  describe "GET #notifications" do
    skip
  end

  describe "GET #update_notifications" do
    skip
  end

  describe "GET #list_users(prefix = nil, hash = nil)" do
    skip
  end
end
