# frozen_string_literal: true

RSpec.describe 'Transaction Envelope Tracking' do
  let!(:account) { create(:account) }
  let!(:user) { create(:user, account:) }
  let!(:transaction) { create(:transaction, account:, name: '123 E Main St Unit A') }

  before { sign_in(user) }

  it 'lists draft and sent envelopes with status and a link to the submission when sent' do
    draft_envelope = create(:envelope, parent_transaction: transaction, name: 'Draft Packet')
    template = create(:template, account:, author: user)
    submission = create(:submission, template:, account:, created_by_user: user)
    sent_envelope = create(:envelope, parent_transaction: transaction, name: 'Sent Packet', status: :sent,
                                      template:, submission:)

    visit transaction_path(transaction)

    expect(page).to have_content('Draft Packet')
    expect(page).to have_content('draft')
    expect(page).to have_content('Sent Packet')
    expect(page).to have_content('sent')
    expect(page).to have_link('View Submission', href: submission_path(sent_envelope.submission))
  end
end
