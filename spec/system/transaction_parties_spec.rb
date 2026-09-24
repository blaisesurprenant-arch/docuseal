# frozen_string_literal: true

RSpec.describe 'Transaction Parties' do
  let!(:account) { create(:account) }
  let!(:user) { create(:user, account:) }
  let!(:transaction) { create(:transaction, account:, name: '123 E Main St Unit A') }

  before { sign_in(user) }

  it 'adds an individual party with an existing role' do
    create(:role, account:, name: 'Buyer')

    visit transaction_path(transaction)
    click_link 'Add Party'

    select 'Buyer', from: 'transaction_party[role_id]'
    fill_in 'transaction_party[first_name]', with: 'Jane'
    fill_in 'transaction_party[last_name]', with: 'Doe'
    fill_in 'transaction_party[email]', with: 'jane@example.com'

    expect do
      click_button 'Add Party'
    end.to change(TransactionParty, :count).by(1)

    expect(page).to have_content('Jane Doe')
    expect(page).to have_content('Buyer')
  end

  it 'adds a new role inline while adding a party' do
    visit transaction_path(transaction)
    click_link 'Add Party'

    select '+ Add new role...', from: 'transaction_party[role_id]'
    fill_in 'new_role_name', with: 'Escrow Agent'
    fill_in 'transaction_party[first_name]', with: 'Sam'
    fill_in 'transaction_party[last_name]', with: 'Lee'
    fill_in 'transaction_party[email]', with: 'sam@example.com'

    expect do
      click_button 'Add Party'
    end.to change(Role, :count).by(1).and change(TransactionParty, :count).by(1)

    expect(account.roles.last.name).to eq('Escrow Agent')
  end

  it 'toggles to a business party and requires signer name/title' do
    create(:role, account:, name: 'Seller')

    visit transaction_path(transaction)
    click_link 'Add Party'

    select 'Seller', from: 'transaction_party[role_id]'
    select 'Business', from: 'transaction_party[party_type]'
    fill_in 'transaction_party[company_name]', with: 'Acme LLC'

    expect do
      click_button 'Add Party'
    end.not_to change(TransactionParty, :count)

    expect(page).to have_content("can't be blank")
  end

  it 'edits an existing party' do
    role = create(:role, account:, name: 'Buyer')
    party = create(:transaction_party, parent_transaction: transaction, role:, first_name: 'Jane', last_name: 'Doe')

    visit transaction_path(transaction)
    click_link 'Edit', href: edit_transaction_transaction_party_path(transaction, party)

    fill_in 'transaction_party[last_name]', with: 'Smith'
    click_button 'Save'

    expect(party.reload.last_name).to eq('Smith')
  end

  it 'propagates an edited email to the linked (still-pending) submitter of a sent envelope' do
    role = create(:role, account:, name: 'Buyer')
    party = create(:transaction_party, parent_transaction: transaction, role:, first_name: 'Jane', last_name: 'Doe',
                                       email: 'jane@example.com')
    template = create(:template, account:, author: user, submitter_count: 1)
    template.submitters[0]['name'] = 'Buyer'
    template.save!
    envelope = create(:envelope, parent_transaction: transaction, name: 'Move-In Packet')
    envelope.envelope_source_templates.create!(source_template: template, position: 0)

    visit transaction_envelope_send_path(transaction, envelope)
    click_button 'Send'

    submitter = envelope.reload.envelope_parts.find_by(transaction_party: party).submitter

    visit edit_transaction_transaction_party_path(transaction, party)
    fill_in 'transaction_party[email]', with: 'jane.doe@newdomain.com'
    click_button 'Save'

    expect(submitter.reload.email).to eq('jane.doe@newdomain.com')
  end

  it 'does not overwrite a submitter that has already completed signing' do
    role = create(:role, account:, name: 'Buyer')
    party = create(:transaction_party, parent_transaction: transaction, role:, first_name: 'Jane', last_name: 'Doe',
                                       email: 'jane@example.com')
    template = create(:template, account:, author: user, submitter_count: 1)
    template.submitters[0]['name'] = 'Buyer'
    template.save!
    envelope = create(:envelope, parent_transaction: transaction, name: 'Move-In Packet')
    envelope.envelope_source_templates.create!(source_template: template, position: 0)

    visit transaction_envelope_send_path(transaction, envelope)
    click_button 'Send'

    submitter = envelope.reload.envelope_parts.find_by(transaction_party: party).submitter
    submitter.update!(completed_at: Time.current)

    visit edit_transaction_transaction_party_path(transaction, party)
    fill_in 'transaction_party[email]', with: 'jane.doe@newdomain.com'
    click_button 'Save'

    expect(submitter.reload.email).to eq('jane@example.com')
  end
end
