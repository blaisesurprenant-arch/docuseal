# frozen_string_literal: true

RSpec.describe 'Envelope Build - Template Picker' do
  let!(:account) { create(:account) }
  let!(:user) { create(:user, account:) }
  let!(:transaction) { create(:transaction, account:) }
  let!(:template_a) { create(:template, account:, author: user, name: 'Lease Agreement') }
  let!(:template_b) { create(:template, account:, author: user, name: 'Disclosure Form') }

  before { sign_in(user) }

  it 'shows the template picker' do
    visit new_transaction_envelope_path(transaction)

    expect(page).to have_content('Lease Agreement')
    expect(page).to have_content('Disclosure Form')
  end

  it 'creates a draft envelope with the selected templates in order' do
    visit new_transaction_envelope_path(transaction)

    fill_in 'envelope[name]', with: 'Move-In Packet'
    check "template_ids_#{template_a.id}"
    check "template_ids_#{template_b.id}"

    expect do
      click_button 'Next: Assign Roles'
    end.to change(Envelope, :count).by(1).and change(EnvelopeSourceTemplate, :count).by(2)

    envelope = transaction.envelopes.last

    expect(envelope).to be_draft
    expect(envelope.source_templates).to eq([template_a, template_b])
  end

  it 'requires at least one template to be selected' do
    visit new_transaction_envelope_path(transaction)

    fill_in 'envelope[name]', with: 'Move-In Packet'

    expect do
      click_button 'Next: Assign Roles'
    end.not_to change(Envelope, :count)

    expect(page).to have_content('Select at least one template')
  end
end
