# frozen_string_literal: true

RSpec.describe Envelope do
  let(:account) { create(:account) }
  let(:transaction) { create(:transaction, account:) }
  let(:author) { create(:user, account:) }

  it 'is valid with a name and defaults to draft status' do
    envelope = create(:envelope, parent_transaction: transaction, name: 'Lease Packet')

    expect(envelope).to be_draft
  end

  it 'tracks its source templates in order' do
    template_a = create(:template, account:, author:)
    template_b = create(:template, account:, author:)
    envelope = create(:envelope, parent_transaction: transaction)

    envelope.envelope_source_templates.create!(source_template: template_a, position: 0)
    envelope.envelope_source_templates.create!(source_template: template_b, position: 1)

    expect(envelope.source_templates).to eq([template_a, template_b])
  end

  it 'tracks which transaction parties are included' do
    role = create(:role, account:)
    party = create(:transaction_party, parent_transaction: transaction, role:)
    envelope = create(:envelope, parent_transaction: transaction)

    envelope.envelope_parts.create!(transaction_party: party)

    expect(envelope.transaction_parties).to eq([party])
  end

  describe '#sync_status_from_submission!' do
    let(:template) { create(:template, account:, author:) }
    let(:submission) { create(:submission, :with_submitters, template:, account:, created_by_user: author) }
    let(:envelope) do
      create(:envelope, parent_transaction: transaction, status: :sent, template:, submission:)
    end

    it 'does nothing without a submission' do
      draft = create(:envelope, parent_transaction: transaction)

      expect { draft.sync_status_from_submission! }.not_to change(draft, :status)
    end

    it 'never resurrects a voided envelope' do
      voided = create(:envelope, parent_transaction: transaction, status: :voided, template:, submission:)
      submission.update!(completed_at: Time.current)

      expect { voided.sync_status_from_submission! }.not_to change(voided, :status)
    end

    it 'moves to completed when the submission completes' do
      submission.update!(completed_at: Time.current)

      envelope.sync_status_from_submission!

      expect(envelope.reload).to be_completed
    end

    it 'moves to declined when any submitter declines' do
      submission.submitters.first.update!(declined_at: Time.current)

      envelope.sync_status_from_submission!

      expect(envelope.reload).to be_declined
    end

    it 'moves to expired when the submission has expired' do
      submission.update!(expire_at: 1.day.ago)

      envelope.sync_status_from_submission!

      expect(envelope.reload).to be_expired
    end

    it 'stays sent while the submission is still pending' do
      envelope.sync_status_from_submission!

      expect(envelope.reload).to be_sent
    end

    it 'syncs automatically when the submission completes, with no manual call' do
      envelope

      submission.update!(completed_at: Time.current)

      expect(envelope.reload).to be_completed
    end

    it 'syncs automatically when a submitter declines, with no manual call' do
      envelope

      submission.submitters.first.update!(declined_at: Time.current)

      expect(envelope.reload).to be_declined
    end
  end
end
