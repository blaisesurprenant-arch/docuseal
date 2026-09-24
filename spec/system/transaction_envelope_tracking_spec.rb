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

  it 'shows the most recent submission activity for a sent envelope' do
    template = create(:template, account:, author: user)
    submission = create(:submission, :with_submitters, template:, account:, created_by_user: user)
    envelope = create(:envelope, parent_transaction: transaction, name: 'Active Packet', status: :sent,
                                 template:, submission:)
    create(:submission_event, submission:, submitter: submission.submitters.first, event_type: 'view_form',
                              event_timestamp: 2.days.ago)
    create(:submission_event, submission:, submitter: submission.submitters.first, event_type: 'complete_form',
                              event_timestamp: 1.hour.ago)

    visit transaction_path(transaction)

    within("[data-envelope-name='Active Packet']") do
      expect(page).to have_content('complete_form')
      expect(page).not_to have_content('view_form')
    end
  end

  it 'shows an expired envelope as expired without any manual status update' do
    template = create(:template, account:, author: user)
    submission = create(:submission, template:, account:, created_by_user: user, expire_at: 1.day.ago)
    envelope = create(:envelope, parent_transaction: transaction, name: 'Stale Packet', status: :sent,
                                 template:, submission:)

    visit transaction_path(transaction)

    expect(page).to have_content('Stale Packet')
    expect(page).to have_content('expired')
    expect(envelope.reload).to be_expired
  end
end
