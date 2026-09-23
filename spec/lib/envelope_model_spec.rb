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
end
