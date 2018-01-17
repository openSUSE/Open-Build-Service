require 'rails_helper'
require 'webmock/rspec'

RSpec.describe Cloud::Backend::UploadJob, type: :model, vcr: true do
  let(:user) { create(:confirmed_user, login: 'tom', ec2_configuration: create(:ec2_configuration)) }
  let(:now) { Time.now }

  describe '.create' do
    let(:params) do
      {
        project:    'Cloud',
        package:    'aws',
        repository: 'standard',
        arch:       'x86_64',
        filename:   'appliance.raw.gz',
        region:     'us-east-1',
        user:       user,
        target:     'ec2',
        ami_name:   'myami'
      }
    end
    let(:xml_response) do
      <<-HEREDOC
      <clouduploadjob name="6">
        <state>created</state>
        <details>waiting to receive image</details>
        <created>#{now.to_i}</created>
        <user>mlschroe</user>
        <target>ec2</target>
        <project>Base:System</project>
        <repository>openSUSE_Factory</repository>
        <package>rpm</package>
        <arch>x86_64</arch>
        <filename>rpm-4.14.0-504.2.x86_64.rpm</filename>
        <size>1690860</size>
      </clouduploadjob>
      HEREDOC
    end
    let(:backend_params) do
      params.except(:region, :ami_name)
    end
    let(:post_body) do
      user.ec2_configuration.attributes.except('id', 'created_at', 'updated_at').
        merge(region: 'us-east-1', ami_name: 'myami').to_json
    end
    let(:path) { "#{CONFIG['source_url']}/cloudupload?#{backend_params.to_param}" }

    context 'with a valid backend response' do
      before do
        stub_request(:post, path).with(body: post_body).and_return(body: xml_response)
      end

      subject { Cloud::Backend::UploadJob.create(params) }

      it { expect(subject.valid?).to be_truthy }
      it { expect(subject.id).to eq('6') }
      it { expect(subject.state).to eq('created') }
      it { expect(subject.details).to eq('waiting to receive image') }
      it { expect(subject.user).to eq('mlschroe') }
      it { expect(subject.target).to eq('ec2') }
      it { expect(subject.project).to eq('Base:System') }
      it { expect(subject.package).to eq('rpm') }
      it { expect(subject.repository).to eq('openSUSE_Factory') }
      it { expect(subject.architecture).to eq('x86_64') }
      it { expect(subject.filename).to eq('rpm-4.14.0-504.2.x86_64.rpm') }
      it { expect(subject.size).to eq('1690860') }
      it { expect(subject.created_at).to be_a(DateTime) }
      it { expect(subject.created_at.to_s).to eq(now.to_datetime.to_s) }
    end

    context 'with an invalid backend response' do
      subject { Cloud::Backend::UploadJob.create(params) }

      it { expect(subject.valid?).to be_falsy }
      it 'has the correct error message' do
        subject.valid?
        expect(subject.errors.full_messages.to_sentence).to eq('no cloud upload server configurated')
      end
    end

    context 'with Timeout::Error' do
      before do
        allow(Backend::Api::Cloud).to receive(:upload).with(params).and_raise(Timeout::Error, 'boom')
      end
      subject { Cloud::Backend::UploadJob.create(params) }

      it { expect(subject.valid?).to be_falsy }
      it 'has the correct error message' do
        subject.valid?
        expect(subject.errors.full_messages.to_sentence).to eq('boom')
      end
    end
  end

  describe '.all' do
    context 'with a valid backend response' do
      let(:upload_job) { create(:upload_job, user: user) }
      context 'with one upload job' do
        let(:xml_response) do
          <<-HEREDOC
            <clouduploadjoblist>
              <clouduploadjob name="2">
                <state>uploading</state>
                <created>1513603428</created>
                <user>mlschroe</user>
                <target>ec2</target>
                <project>Base:System</project>
                <repository>openSUSE_Factory</repository>
                <package>rpm</package>
                <arch>x86_64</arch>
                <filename>rpm-4.14.0-504.2.x86_64.rpm</filename>
                <size>1690860</size>
                <pid>18788</pid>
              </clouduploadjob>
            </clouduploadjoblist>
          HEREDOC
        end
        let(:path) { "#{CONFIG['source_url']}/cloudupload?name=#{upload_job.job_id}" }

        before do
          stub_request(:get, path).and_return(body: xml_response)
        end

        subject { Cloud::Backend::UploadJob.all(user) }

        it { expect(subject.length).to eq(1) }
        it { expect(subject.first.id).to eq('2') }
      end

      context 'with more than one upload job' do
        let(:another_upload_job) { create(:upload_job, user: user) }
        let(:xml_response) do
          <<-HEREDOC
            <clouduploadjoblist>
              <clouduploadjob name="2">
                <state>uploading</state>
                <created>1513603428</created>
                <user>mlschroe</user>
                <target>ec2</target>
                <project>Base:System</project>
                <repository>openSUSE_Factory</repository>
                <package>rpm</package>
                <arch>x86_64</arch>
                <filename>rpm-4.14.0-504.2.x86_64.rpm</filename>
                <size>1690860</size>
                <pid>18788</pid>
              </clouduploadjob>
              <clouduploadjob name="3">
                <state>uploading</state>
                <created>1513603663</created>
                <user>mlschroe</user>
                <target>ec2</target>
                <project>Base:System</project>
                <repository>openSUSE_Factory</repository>
                <package>rpm</package>
                <arch>x86_64</arch>
                <filename>rpm-4.14.0-504.2.x86_64.rpm</filename>
                <size>1690860</size>
                <pid>18790</pid>
              </clouduploadjob>
            </clouduploadjoblist>
          HEREDOC
        end
        let(:path) { "#{CONFIG['source_url']}/cloudupload?name=#{upload_job.job_id}&name=#{another_upload_job.job_id}" }

        before do
          stub_request(:get, path).and_return(body: xml_response)
        end

        subject { Cloud::Backend::UploadJob.all(user) }

        it { expect(subject.length).to eq(2) }
        it { expect(subject.first.id).to eq('2') }
        it { expect(subject.second.id).to eq('3') }
      end

      context 'with no upload job' do
        let(:xml_response) do
          <<-HEREDOC
            <clouduploadjoblist>
            </clouduploadjoblist>
          HEREDOC
        end
        let(:path) { "#{CONFIG['source_url']}/cloudupload" }

        before do
          stub_request(:get, path).and_return(body: xml_response)
        end

        subject { Cloud::Backend::UploadJob.all(user) }

        it { expect(subject).to be_empty }
      end
    end

    context 'with an invalid backend response' do
      subject { Cloud::Backend::UploadJob.all(user) }

      it { expect(subject).to be_empty }
    end

    context 'with Timeout::Error' do
      before do
        allow(Backend::Api::Cloud).to receive(:status).with(user).and_raise(Timeout::Error, 'boom')
      end
      subject { Cloud::Backend::UploadJob.all(user) }

      it { expect(subject).to be_empty }
    end
  end
end
