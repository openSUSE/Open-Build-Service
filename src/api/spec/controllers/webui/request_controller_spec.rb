require 'rails_helper'
# WARNING: If you change changerequest tests make sure you uncomment this line
# and start a test backend. Some of the methods require real backend answers
# for projects/packages.
# CONFIG['global_write_through'] = true

RSpec.describe Webui::RequestController, vcr: true do
  let(:submitter) { create(:confirmed_user, login: 'kugelblitz' ) }
  let(:receiver) { create(:confirmed_user, login: 'titan' ) }
  let(:reviewer) { create(:confirmed_user, login: 'klasnic' ) }
  let(:target_project) { receiver.home_project }
  let(:target_package) { create(:package, name: 'goal', project_id: target_project.id) }
  let(:source_project) { submitter.home_project }
  let(:source_package) { create(:package, name: 'ball', project_id: source_project.id) }
  let(:devel_project) { create(:project, name: 'devel:project') }
  let(:devel_package) { create(:package_with_file, name: 'goal', project: devel_project) }
  let(:bs_request) { create(:bs_request, description: "Please take this", creator: submitter.login) }
  let(:create_submit_request) do
    bs_request.bs_request_actions.delete_all
    create(:bs_request_action_submit, target_project: target_project.name,
                                      target_package: target_package.name,
                                      source_project: source_project.name,
                                      source_package: source_package.name,
                                      bs_request_id: bs_request.id)
  end
  let(:request_with_review) do
    create(:review_bs_request,
           reviewer: reviewer,
           target_project: target_project.name,
           target_package: target_package.name,
           source_project: source_project.name,
           source_package: source_package.name)
  end

  it { is_expected.to use_before_action(:require_login) }
  it { is_expected.to use_before_action(:require_request) }

  describe 'GET show' do
    it 'is successful as nobody' do
      get :show, params: { number: bs_request.number }
      expect(response).to have_http_status(:success)
    end

    it 'assigns @bs_request' do
      get :show, params: { number: bs_request.number }
      expect(assigns(:bs_request)).to eq(bs_request)
    end

    it 'redirects to root_path if request does not exist' do
      login submitter
      get :show, params: { number: '200000' }
      expect(flash[:error]).to eq("Can't find request 200000")
      expect(response).to redirect_to(user_show_path(User.current))
    end

    it 'shows a hint to project maintainers when there are package maintainers' do
      login receiver

      create_submit_request

      # the hint will only be shown, when the target package has at least one
      # maintainer. so we'll gonna add a maintainer to the target package
      create(:relationship_package_user, user: submitter, package: target_package)

      get :show, params: { number: bs_request.number }

      expect(assigns(:show_project_maintainer_hint)).to eq(true)
    end

    it 'does not show a hint to project maintainers if the target package has no maintainers' do
      login receiver

      create_submit_request

      get :show, params: { number: bs_request.number }

      expect(assigns(:show_project_maintainer_hint)).to eq(false)
    end
  end

  describe "POST #delete_request" do
    before do
      login(submitter)
    end

    context "a valid request" do
      before do
        post :delete_request, params: { project: target_project, package: target_package, description: "delete it!" }
        @bs_request = BsRequest.joins(:bs_request_actions).
          where("bs_request_actions.target_project=? AND bs_request_actions.target_package=? AND type=?",
                target_project.to_s, target_package.to_s, "delete"
               ).first
      end

      it { expect(response).to redirect_to(request_show_path(number: @bs_request)) }
      it { expect(flash[:success]).to match("Created .+repository delete request #{@bs_request.number}") }
      it { expect(@bs_request).not_to be nil }
      it { expect(@bs_request.description).to eq("delete it!") }
    end

    context "a request causing a APIException" do
      before do
        allow_any_instance_of(BsRequest).to receive(:save!).and_raise(APIException, "something happened")
        post :delete_request, params: { project: target_project, package: target_package, description: "delete it!" }
      end

      it { expect(flash[:error]).to eq("something happened") }
      it { expect(response).to redirect_to(package_show_path(project: target_project, package: target_package)) }

      it "does not create a delete request" do
        expect(BsRequest.count).to eq(0)
      end
    end
  end

  describe "POST #modify_review" do
    before do
      login(reviewer)
    end

    context "with valid parameters" do
      before do
        post :modify_review, params: { review_comment_0:        "yeah",
                                       review_request_number_0: request_with_review.number,
                                       review_by_user_0:        reviewer,
                                       accepted:                'Approve' }
      end

      it { expect(response).to redirect_to(request_show_path(number: request_with_review.number)) }
      it { expect(request_with_review.reload.reviews.last.state).to eq(:accepted) }
    end

    context "with invalid parameters" do
      it 'without request' do
        post :modify_review, params: { review_comment_0:        "yeah",
                                       review_request_number_0: 1899,
                                       review_by_user_0:        reviewer,
                                       accepted:                "Approve"}
        expect(flash[:error]).to eq('Unable to load request')
        expect(request_with_review.reload.reviews.last.state).to eq(:new)
        expect(request_with_review.reload.state).to eq(:review)
      end
      it 'without state' do
        post :modify_review, params: { review_comment_0:        "yeah",
                                       review_request_number_0: request_with_review.number,
                                       review_by_user_0:        reviewer}
        expect(flash[:error]).to eq('Unknown state to set')
        expect(request_with_review.reload.reviews.last.state).to eq(:new)
        expect(request_with_review.reload.state).to eq(:review)
      end
      it "without permissions" do
        post :modify_review, params: { review_comment_0:        "yeah",
                                       review_request_number_0: request_with_review.number,
                                       review_by_user_0:        submitter,
                                       accepted:                'Approve' }
        expect(flash[:error]).to eq("Not permitted to change review state: review state change is not permitted for #{reviewer.login}")
        expect(request_with_review.reload.reviews.last.state).to eq(:new)
        expect(request_with_review.reload.state).to eq(:review)
      end
      it "with invalid transition" do
        request_with_review.update_attributes(state: 'declined')
        post :modify_review, params: { review_comment_0:        "yeah",
                                       review_request_number_0: request_with_review.number,
                                       review_by_user_0:        reviewer,
                                       accepted:                'Approve' }
        expect(flash[:error]).to eq("Not permitted to change review state: The request is neither in state review nor new")
        expect(request_with_review.reload.state).to eq(:declined)
      end
    end
  end

  describe "POST #changerequest" do
    before do
      create_submit_request
    end

    context "with valid parameters" do
      it 'accepts' do
        login(receiver)
        post :changerequest, params: {
          number: bs_request.number, accepted: 'accepted'
        }
        expect(bs_request.reload.state).to eq(:accepted)
      end

      it 'declines' do
        login(receiver)
        post :changerequest, params: {
          number: bs_request.number, declined: 'declined'
        }
        expect(bs_request.reload.state).to eq(:declined)
      end

      it 'revokes' do
        login(submitter)
        post :changerequest, params: {
          number: bs_request.number, revoked: 'revoked'
        }
        expect(bs_request.reload.state).to eq(:revoked)
      end

      it 'adds submitter as maintainer' do
        login(receiver)
        post :changerequest, params: {
          number: bs_request.number, accepted: 'accepted', add_submitter_as_maintainer_0: "#{target_project}_#_#{target_package}"
        }
        expect(bs_request.reload.state).to eq(:accepted)
        expect(target_package.relationships.map(&:user_id).include?(submitter.id)).to be_truthy
      end

      it 'forwards' do
        login(receiver)
        expect {
          post :changerequest, params: {
              number: bs_request.number, accepted: 'accepted',
              forward_devel_0: "#{devel_package.project}_#_#{devel_package}",
              description: 'blah blah blah'
            }}.to change { BsRequest.count }.by(1)
        expect(BsRequest.last.bs_request_actions).to eq(devel_package.project.target_of_bs_request_actions)
      end
    end

    context "with invalid parameters" do
      it 'without request' do
        login(receiver)
        post :changerequest, params: {
          number: 1899, accepted: 'accepted'
        }
        expect(flash[:error]).to eq('Can\'t find request 1899')
      end
    end

    context "when forwarding the request fails" do
      before do
        allow(BsRequestActionSubmit).to receive(:new).and_raise(APIException, 'some error')
        login(receiver)
      end

      it 'accepts the parent request and reports an error for the forwarded request' do
        expect {
          post :changerequest, params: {
              number: bs_request.number, accepted: 'accepted',
              forward_devel_0: "#{devel_package.project}_#_#{devel_package}",
              description: 'blah blah blah'
            }}.not_to change(BsRequest, :count)
        expect(bs_request.reload.state).to eq(:accepted)
        expect(flash[:notice]).to match("Request \\d accepted")
        expect(flash[:error]).to eq('Unable to forward submit request: some error')
      end
    end
  end

  describe "POST #change_devel_request" do
    context "with valid parameters" do
      before do
        login(submitter)
        post :change_devel_request, params: {
            project: target_project.name, package: target_package.name,
            devel_project: source_project.name, devel_package: source_package.name, description: "change it!"
          }
        @bs_request = BsRequest.where(description: "change it!", creator: submitter.login, state: "new").first
      end

      it { expect(response).to redirect_to(request_show_path(number: @bs_request)) }
      it { expect(flash[:success]).to be nil }
      it { expect(@bs_request).not_to be nil }
      it { expect(@bs_request.description).to eq("change it!") }

      it "creates a request action with correct data" do
        request_action = @bs_request.bs_request_actions.where(
          type: "change_devel",
          target_project: target_project.name,
          target_package: target_package.name,
          source_project: source_project.name,
          source_package: source_package.name
        )
        expect(request_action).to exist
      end
    end

    context "with invalid devel_package parameter" do
      before do
        login(submitter)
        post :change_devel_request, params: {
            project: target_project.name, package: target_package.name,
            devel_project: source_project.name, devel_package: "non-existant", description: "change it!"
          }
        @bs_request = BsRequest.where(description: "change it!", creator: submitter.login, state: "new").first
      end

      it { expect(flash[:error]).to eq("No such package: #{source_project.name}/non-existant") }
      it { expect(response).to redirect_to(package_show_path(project: target_project, package: target_package)) }
      it { expect(@bs_request).to be nil }
    end
  end

  describe "POST #sourcediff" do
    context "with xhr header" do
      before do
        post :sourcediff, xhr: true
      end

      it { expect(response).to have_http_status(:success) }
      it { expect(response).to render_template('shared/_editor') }
    end

    context "without xhr header" do
      let(:call_sourcediff) { post :sourcediff }

      it { expect{ call_sourcediff }.to raise_error(ActionController::RoutingError, 'Expected AJAX call') }
    end
  end
end
