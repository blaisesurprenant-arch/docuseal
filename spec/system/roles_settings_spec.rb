# frozen_string_literal: true

RSpec.describe 'Roles Settings' do
  let!(:account) { create(:account) }
  let!(:user) { create(:user, account:) }

  before { sign_in(user) }

  it 'shows an empty state when there are no roles' do
    visit settings_roles_path

    expect(page).to have_content('Roles')
    expect(page).to have_field('role[name]')
  end

  it 'creates a role' do
    visit settings_roles_path

    fill_in 'role[name]', with: 'Buyer'

    expect do
      click_button 'Add Role'
    end.to change(Role, :count).by(1)

    expect(account.roles.last.name).to eq('Buyer')
    expect(page).to have_content('Buyer')
  end

  it 'rejects a duplicate role name' do
    create(:role, account:, name: 'Buyer')

    visit settings_roles_path
    fill_in 'role[name]', with: 'Buyer'

    expect do
      click_button 'Add Role'
    end.not_to change(Role, :count)

    expect(page).to have_content('has already been taken')
  end

  it 'renames a role' do
    role = create(:role, account:, name: 'Buyer')

    visit settings_roles_path
    within "#role_#{role.id}" do
      fill_in "roles[#{role.id}][name]", with: 'Purchaser'
      click_button 'Save'
    end

    expect(role.reload.name).to eq('Purchaser')
  end

  it 'creates a CC / view-only role' do
    visit settings_roles_path

    fill_in 'role[name]', with: 'Notary'
    check 'role[is_viewer]'

    expect do
      click_button 'Add Role'
    end.to change(Role, :count).by(1)

    expect(account.roles.last).to be_is_viewer
  end

  it 'toggles a role to CC / view-only' do
    role = create(:role, account:, name: 'Lender', is_viewer: false)

    visit settings_roles_path
    within "#role_#{role.id}" do
      check "roles[#{role.id}][is_viewer]"
      click_button 'Save'
    end

    expect(role.reload).to be_is_viewer
  end

  it 'deletes an unused role' do
    create(:role, account:, name: 'Buyer')

    visit settings_roles_path

    expect do
      accept_confirm { click_button 'Delete' }
    end.to change(Role, :count).by(-1)
  end

  it 'shows an error instead of deleting a role still in use' do
    role = create(:role, account:, name: 'Buyer')
    transaction = create(:transaction, account:)
    create(:transaction_party, parent_transaction: transaction, role:)

    visit settings_roles_path

    expect do
      accept_confirm { click_button 'Delete' }
    end.not_to change(Role, :count)

    expect(page).to have_content('still in use')
  end
end
