# frozen_string_literal: true

RSpec.describe 'Envelope Build - Edit Merged Document Before Sending' do
  let!(:account) { create(:account) }
  let!(:user) { create(:user, account:) }
  let!(:transaction) { create(:transaction, account:) }
  let!(:buyer_role) { create(:role, account:, name: 'Buyer') }
  let!(:buyer) { create(:transaction_party, parent_transaction: transaction, role: buyer_role, first_name: 'Jane', last_name: 'Doe', email: 'jane@example.com') }

  let!(:template) do
    t = create(:template, account:, author: user, submitter_count: 1)
    t.submitters[0]['name'] = 'Buyer'
    t.save!
    t
  end

  let!(:envelope) do
    e = create(:envelope, parent_transaction: transaction, name: 'Move-In Packet')
    e.envelope_source_templates.create!(source_template: template, position: 0)
    e
  end

  before { sign_in(user) }

  it 'merges the template as soon as the choose-parties page is visited, before sending' do
    expect do
      visit transaction_envelope_send_path(transaction, envelope)
    end.to change(Template, :count).by(1)

    envelope.reload
    expect(envelope.template).to be_present
    expect(envelope).to be_draft
  end

  it 'offers a link to edit the merged document before sending' do
    visit transaction_envelope_send_path(transaction, envelope)

    expect(page).to have_link('Edit Document', href: edit_template_path(envelope.reload.template))
  end

  it 'does not re-merge (or create a second template) on a repeat visit or on send' do
    visit transaction_envelope_send_path(transaction, envelope)
    merged_template_id = envelope.reload.template_id

    expect do
      visit transaction_envelope_send_path(transaction, envelope)
      click_button 'Send'
    end.to change(Submission, :count).by(1).and change(Template, :count).by(0)

    expect(envelope.reload.template_id).to eq(merged_template_id)
  end

  it 're-merges after the document set changes' do
    visit transaction_envelope_send_path(transaction, envelope)
    first_template_id = envelope.reload.template_id

    other_template = create(:template, account:, author: user, submitter_count: 1)
    other_template.submitters[0]['name'] = 'Buyer'
    other_template.save!

    visit edit_transaction_envelope_path(transaction, envelope)
    check "template_ids_#{other_template.id}"
    click_button 'Save'

    expect(envelope.reload.template_id).to be_nil

    visit transaction_envelope_send_path(transaction, envelope)

    expect(envelope.reload.template_id).not_to eq(first_template_id)
    expect(envelope.template.fields.size).to eq(template.fields.size + other_template.fields.size)
  end
end
