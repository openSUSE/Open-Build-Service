require 'rails_helper'

RSpec.describe Token::Rebuild do
  let(:user) { create(:user, login: 'foo') }
  let(:token) { create(:rebuild_token, user: user) }

  subject { token.call(package: 'bar') }

  describe '#call' do
    context 'successful triggered' do
      before do
        allow(Backend::Api::Sources::Package).to receive(:rebuild).and_return(true)
      end

      it 'records the current date and time in the triggered_at column' do
        expect { subject }.to(change(token, :triggered_at))
      end
    end

    context 'triggered without success' do
      before do
        allow(Backend::Api::Sources::Package).to receive(:rebuild).and_raise(Backend::Error, 'something went wrong')
      end

      it 'records the current date and time in the triggered_at column' do
        expect { subject }.to raise_error(Backend::Error).and(change(token, :triggered_at))
      end
    end
  end
end
