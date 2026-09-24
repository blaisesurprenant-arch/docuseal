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

  it 'shows a Void link only for sent envelopes' do
    visit transaction_path(transaction)

    expect(page).to have_link('Void')
  end

  it 'does not show a Void link for a draft envelope' do
    create(:envelope, parent_transaction: transaction, name: 'Draft Packet')

    visit transaction_path(transaction)

    within("[data-envelope-name='Draft Packet']") do
      expect(page).not_to have_link('Void')
    end
  end

  it 'requires a reason before voiding' do
    visit transaction_path(transaction)
    click_link 'Void'
    click_button 'Void Envelope'

    expect(page).to have_content('A reason is required')
    expect(envelope.reload).to be_sent
  end

  it 'voids the envelope with a reason and archives its submission' do
    visit transaction_path(transaction)
    click_link 'Void'
    fill_in 'envelope[void_reason]', with: 'Buyer backed out of the deal'
    click_button 'Void Envelope'

    expect(page).to have_content('Envelope has been voided.')
    expect(envelope.reload).to be_voided
    expect(envelope.void_reason).to eq('Buyer backed out of the deal')
    expect(submission.reload.archived_at).to be_present
  end
end
