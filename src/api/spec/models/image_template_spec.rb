require "rails_helper"
require "webmock/rspec"

RSpec.describe Project do
  describe '.remote_image_templates' do
    let!(:remote_instance) { create(:project, name: 'RemoteProject', remoteurl: 'http://example.com/public') }

    before do
      stub_request(:get, 'http://example.com/public/image_templates.xml')
        .and_return(body: %(<image_template_projects>
                              <image_template_project name='Images'>
                                <image_template_package>
                                  <name>leap-42-1-jeos</name>
                                   <title/>
                                    <description/>
                                </image_template_package>
                              </image_template_project>
                          </image_template_projects>
                         )
                   )
      @images = Project.remote_image_templates
    end

    it { expect(@images.class).to eq(Array) }

    context 'with one remote instance' do
      context 'and one package' do
        it { expect(@images.length).to eq(1) }
        it { expect(@images.first.name).to eq('RemoteProject:Images') }
        it { expect(@images.first.packages.first.name).to eq('leap-42-1-jeos') }
      end

      context 'and two projects' do
        before do
          stub_request(:get, 'http://example.com/public/image_templates.xml')
            .and_return(body: %(<image_template_projects>
                              <image_template_project name='Images'>
                                <image_template_package>
                                  <name>leap-42-1-jeos</name>
                                   <title/>
                                    <description/>
                                </image_template_package>
                              </image_template_project>
                              <image_template_project name='Foobar'>
                                <image_template_package>
                                  <name>leap-42-2-jeos</name>
                                   <title/>
                                    <description/>
                                </image_template_package>
                              </image_template_project>
                          </image_template_projects>
                         )
                       )
          @images = Project.remote_image_templates
        end

        it { expect(@images.length).to eq(2) }
        it { expect(@images.second.name).to eq('RemoteProject:Foobar') }
        it { expect(@images.second.packages.first.name).to eq('leap-42-2-jeos') }
      end

      context 'and two packages' do
        before do
          stub_request(:get, 'http://example.com/public/image_templates.xml')
            .and_return(body: %(<image_template_projects>
                              <image_template_project name='Images'>
                                <image_template_package>
                                  <name>leap-42-1-jeos</name>
                                   <title/>
                                    <description/>
                                </image_template_package>
                                <image_template_package>
                                  <name>leap-42-2-jeos</name>
                                   <title/>
                                    <description/>
                                </image_template_package>
                              </image_template_project>
                          </image_template_projects>
                         )
                       )
          @images = Project.remote_image_templates
        end

        it { expect(@images.first.packages.length).to eq(2) }
        it { expect(@images.first.packages.second.name).to eq('leap-42-2-jeos') }
      end
    end

    context 'with two remote instances' do
      let!(:another_remote_instance) { create(:project, name: 'AnotherRemoteProject', remoteurl: 'http://example.com/public') }
      before do
        # The AnotherRemoteProject will simply take the request of RemoteInstance defined in the first before filter
        @images = Project.remote_image_templates
      end

      it { expect(@images.length).to eq(2) }
      it { expect(@images.second.name).to eq('AnotherRemoteProject:Images') }
      it { expect(@images.second.packages.first.name).to eq('leap-42-1-jeos') }
    end
  end
end
