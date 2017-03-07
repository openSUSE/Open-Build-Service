require 'rails_helper'

RSpec.describe Webui::ApidocsController, type: :controller do
  describe "GET index" do
    context "correct setup" do
      before do
        get :index
      end

      it "responses without error" do
        expect(response.status).to eq(200)
        expect(response.content_type).to eq "text/html"
      end
    end

    context "broken setup" do
      let!(:old_location) { CONFIG['apidocs_location'] }

      before do
        CONFIG['apidocs_location'] = '/your/mom'
      end

      after do
        CONFIG['apidocs_location'] = old_location
      end

      it "errors and redirects" do
        expect(Rails.logger).to receive(:error).with(
          "Unable to load apidocs index file from #{CONFIG['apidocs_location']}. Did you create the apidocs?"
        )

        get :index

        expect(flash[:error]).to eq("Unable to load API documentation.")
        expect(response).to redirect_to(root_path)
      end
    end
  end

  describe "Non existing sub page" do
    let(:non_existing_filename) { "whatisthis" }

    before do
      get :file, params: { filename: non_existing_filename }
    end

    it "errors and redirects" do
      expect(flash[:error]).to eq("File not found: #{non_existing_filename}")
      expect(response).to redirect_to({ controller: 'apidocs', action: 'index' })
    end
  end
end
