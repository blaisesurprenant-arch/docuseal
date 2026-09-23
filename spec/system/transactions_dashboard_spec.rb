# frozen_string_literal: true

RSpec.describe 'Transactions Dashboard' do
  let!(:account) { create(:account) }
  let!(:user) { create(:user, account:) }

  before { sign_in(user) }

  it 'shows the transactions tab as a peer to templates/submissions' do
    create(:template, account:, author: user)

    visit root_path

    expect(page).to have_css('form#templates_submissions_toggle toggle-cookies[data-value="transactions"]')
  end

  it 'shows an empty state with no transactions' do
    visit transactions_path

    expect(page).to have_content('Transactions')
    expect(page).to have_link('New Transaction')
  end

  it 'lists existing transactions' do
    transaction = create(:transaction, account:, name: '123 E Main St Unit A')

    visit transactions_path

    expect(page).to have_link('123 E Main St Unit A', href: transaction_path(transaction))
  end

  it 'creates a transaction' do
    visit transactions_path
    click_link 'New Transaction'

    fill_in 'transaction[name]', with: '123 E Main St Unit A'

    expect do
      click_button 'Create Transaction'
    end.to change(Transaction, :count).by(1)

    expect(page).to have_content('123 E Main St Unit A')
  end
end
