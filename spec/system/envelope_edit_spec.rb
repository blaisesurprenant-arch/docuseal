# frozen_string_literal: true

RSpec.describe 'Envelope Build - Edit Documents' do
  let!(:account) { create(:account) }
  let!(:user) { create(:user, account:) }
  let!(:transaction) { create(:transaction, account:) }
  let!(:template_a) { create(:template, account:, author: user, name: 'Lease Agreement') }
  let!(:template_b) { create(:template, account:, author: user, name: 'Disclosure Form') }
  let!(:template_c) { create(:template, account:, author: user, name: 'Addendum') }

  let!(:envelope) do
    e = create(:envelope, parent_transaction: transaction, name: 'Move-In Packet')
    e.envelope_source_templates.create!(source_template: template_a, position: 0)
    e
  end

  before { sign_in(user) }

  it 'shows an Edit link for a draft envelope' do
    visit transaction_path(transaction)

    within("[data-envelope-name='Move-In Packet']") do
      expect(page).to have_link('Edit')
    end
  end

  it 'preselects the envelope current templates when editing' do
    visit edit_transaction_envelope_path(transaction, envelope)

    expect(page).to have_field("template_ids_#{template_a.id}", checked: true)
    expect(page).to have_field("template_ids_#{template_b.id}", checked: false)
  end

  it 'changes which templates are attached to a draft envelope' do
    visit edit_transaction_envelope_path(transaction, envelope)

    uncheck "template_ids_#{template_a.id}"
    check "template_ids_#{template_b.id}"
    check "template_ids_#{template_c.id}"
    click_button 'Save'

    expect(envelope.reload.source_templates).to eq([template_b, template_c])
  end

  it 'does not allow editing a sent envelope' do
    sent_template = create(:template, account:, author: user)
    submission = create(:submission, template: sent_template, account:, created_by_user: user)
    create(:envelope, parent_transaction: transaction, name: 'Sent Packet', status: :sent,
                       template: sent_template, submission:)

    visit transaction_path(transaction)

    within("[data-envelope-name='Sent Packet']") do
      expect(page).not_to have_link('Edit')
    end
  end
end
