# frozen_string_literal: true

RSpec.describe 'Voiding a Sent Envelope' do
  let!(:account) { create(:account) }
  let!(:user) { create(:user, account:) }
  let!(:transaction) { create(:transaction, account:) }
  let!(:template) { create(:template, account:, author: user) }
  let!(:submission) { create(:submission, template:, account:, created_by_user: user) }
  let!(:envelope) do
    create(:envelope, parent_transaction: transaction, name: 'Move-In Packet', status: :sent, template:, submission:)
  end

  before { sign_in(user) }

  it 'shows a Void button only for sent envelopes' do
    visit transaction_path(transaction)

    expect(page).to have_button('Void')
  end

  it 'does not show a Void button for a draft envelope' do
    create(:envelope, parent_transaction: transaction, name: 'Draft Packet')

    visit transaction_path(transaction)

    within("[data-envelope-name='Draft Packet']") do
      expect(page).not_to have_button('Void')
    end
  end

  it 'voids the envelope and archives its submission' do
    visit transaction_path(transaction)

    accept_confirm { click_button 'Void' }

    expect(page).to have_content('Envelope has been voided.')
    expect(envelope.reload).to be_voided
    expect(submission.reload.archived_at).to be_present
  end
end
