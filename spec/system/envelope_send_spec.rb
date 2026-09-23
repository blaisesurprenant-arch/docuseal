# frozen_string_literal: true

RSpec.describe 'Envelope Build - Choose Parties and Send' do
  let!(:account) { create(:account) }
  let!(:user) { create(:user, account:) }
  let!(:transaction) { create(:transaction, account:) }
  let!(:buyer_role) { create(:role, account:, name: 'Buyer') }
  let!(:seller_role) { create(:role, account:, name: 'Seller') }
  let!(:buyer) { create(:transaction_party, parent_transaction: transaction, role: buyer_role, first_name: 'Jane', last_name: 'Doe', email: 'jane@example.com') }
  let!(:seller) { create(:transaction_party, parent_transaction: transaction, role: seller_role, first_name: 'Sam', last_name: 'Lee', email: 'sam@example.com') }

  let!(:template) do
    t = create(:template, account:, author: user, submitter_count: 2)
    t.submitters[0]['name'] = 'Buyer'
    t.submitters[1]['name'] = 'Seller'
    t.save!
    t
  end

  let!(:envelope) do
    e = create(:envelope, parent_transaction: transaction, name: 'Move-In Packet')
    e.envelope_source_templates.create!(source_template: template, position: 0)
    e
  end

  before { sign_in(user) }

  it 'defaults to including every resolved party' do
    visit transaction_envelope_send_path(transaction, envelope)

    expect(page).to have_field('party_ids[]', checked: true, count: 2)
  end

  it 'sends the envelope to the checked parties, creating a merged template and submission' do
    expect do
      visit transaction_envelope_send_path(transaction, envelope)
      uncheck "party_ids_#{seller.id}"
      click_button 'Send'
    end.to change(Submission, :count).by(1).and change(Template, :count).by(1)

    envelope.reload

    expect(envelope).to be_sent
    expect(envelope.transaction_parties).to eq([buyer])
    expect(envelope.submission.submitters.count).to eq(1)
    expect(envelope.submission.submitters.first.email).to eq('jane@example.com')
  end

  it 'blocks sending with zero parties included' do
    visit transaction_envelope_send_path(transaction, envelope)
    uncheck "party_ids_#{buyer.id}"
    uncheck "party_ids_#{seller.id}"

    expect do
      click_button 'Send'
    end.not_to change(Submission, :count)

    expect(page).to have_content('Select at least one party')
    expect(envelope.reload).to be_draft
  end
end
