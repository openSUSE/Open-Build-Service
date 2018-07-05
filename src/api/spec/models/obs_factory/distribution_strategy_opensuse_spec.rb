require 'rails_helper'

RSpec.describe ObsFactory::DistributionStrategyOpenSUSE do
  let(:project) { create(:project, name: 'openSUSE:Leap:42.3') }
  let(:distribution) { ObsFactory::Distribution.new(project) }
  let(:strategy) { distribution.strategy }

  describe '#openqa_version' do
    it { expect(strategy.openqa_version).to eq('42') }
  end

  describe '#opensuse_version' do
    it { expect(strategy.opensuse_version).to eq('Leap:42.3') }
  end

  describe '#opensuse_leap_version' do
    it { expect(strategy.opensuse_leap_version).to eq('42.3') }
  end

  describe '#openqa_group' do
    it { expect(strategy.openqa_group).to eq('openSUSE Leap 42.3') }
  end

  describe '#repo_url' do
    it { expect(strategy.repo_url).to eq('http://download.opensuse.org/distribution/leap/42.3/repo/oss/media.1/media') }
  end

  describe '#url_suffix' do
    it { expect(strategy.url_suffix).to eq('distribution/leap/42.3/iso') }
  end

  describe '#openqa_iso_prefix' do
    it { expect(strategy.openqa_iso_prefix).to eq('openSUSE-Leap:42.3-Staging') }
  end

  describe '#published_arch' do
    it { expect(strategy.published_arch).to eq('x86_64') }
  end

  describe '#test_dvd_prefix' do
    it { expect(strategy.test_dvd_prefix).to eq('000product:openSUSE-dvd5-dvd') }
  end

  describe '#totest_version_file' do
    it { expect(strategy.totest_version_file).to eq('images/local/000product:openSUSE-cd-mini-x86_64') }
  end

  describe '#published_version' do
    let(:file) { StringIO.new('openSUSE-42.3-x86_64-Build317.2') }

    before do
      allow_any_instance_of(ObsFactory::DistributionStrategyOpenSUSE).to receive(:open).and_return(file)
    end

    it { expect(strategy.published_version).to eq('317.2') }
  end

  describe '#openqa_filter' do
    let(:project_staging_a) { create(:project, name: 'openSUSE:Leap:42.3:Staging:A') }
    let(:staging_project) { ObsFactory::StagingProject.new(project: project_staging_a, distribution: distribution) }

    it { expect(strategy.openqa_filter(staging_project)).to eq('match=42.3:S:A') }
  end
end
