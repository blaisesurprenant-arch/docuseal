# frozen_string_literal: true

RSpec.describe 'Envelope Build - Role Resolution' do
  let!(:account) { create(:account) }
  let!(:user) { create(:user, account:) }
  let!(:transaction) { create(:transaction, account:) }
  let!(:buyer_role) { create(:role, account:, name: 'Buyer') }
  let!(:buyer_party) { create(:transaction_party, parent_transaction: transaction, role: buyer_role, first_name: 'Jane', last_name: 'Doe') }

  before { sign_in(user) }

  def build_envelope_with_roles(*role_names)
    template = create(:template, account:, author: user, submitter_count: role_names.size)
    template.submitters.each_with_index { |s, i| s['name'] = role_names[i] }
    template.save!

    envelope = create(:envelope, parent_transaction: transaction, name: 'Test Envelope')
    envelope.envelope_source_templates.create!(source_template: template, position: 0)
    envelope
  end

  it 'auto-resolves when the template role matches an existing party by name' do
    envelope = build_envelope_with_roles('Buyer')

    visit transaction_envelope_roles_path(transaction, envelope)

    expect(page).to have_content('All roles resolved')
    expect(page).to have_link('Next: Choose Parties')
  end

  it 'blocks progress and prompts to resolve an unmatched role' do
    envelope = build_envelope_with_roles('Buyer', 'Agent')

    visit transaction_envelope_roles_path(transaction, envelope)

    expect(page).to have_content('Agent')
    expect(page).not_to have_link('Next: Choose Parties')
    expect(page).to have_button('Add Party for This Role')
  end

  it 'resolves an unmatched role by adding a new party for it, then unblocks progress' do
    envelope = build_envelope_with_roles('Buyer', 'Agent')

    visit transaction_envelope_roles_path(transaction, envelope)
    click_button 'Add Party for This Role'

    expect(page).to have_field('transaction_party[role_id]', with: Role.find_by(name: 'Agent').id.to_s)

    fill_in 'transaction_party[first_name]', with: 'Sam'
    fill_in 'transaction_party[last_name]', with: 'Lee'
    click_button 'Add Party'

    expect(page).to have_content('All roles resolved')
  end

  it 'resolves trivially when the template has no role placeholders' do
    template = create(:template, account:, author: user, submitter_count: 0)
    template.submitters = []
    template.save!
    envelope = create(:envelope, parent_transaction: transaction, name: 'No Roles Envelope')
    envelope.envelope_source_templates.create!(source_template: template, position: 0)

    visit transaction_envelope_roles_path(transaction, envelope)

    expect(page).to have_content('All roles resolved')
  end
end
