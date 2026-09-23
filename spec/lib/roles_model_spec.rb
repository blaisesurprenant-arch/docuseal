# frozen_string_literal: true

RSpec.describe Role do
  let(:account) { create(:account) }

  it 'is valid with a unique name for the account' do
    role = build(:role, account:, name: 'Buyer')

    expect(role).to be_valid
  end

  it 'is invalid without a name' do
    role = build(:role, account:, name: '')

    expect(role).not_to be_valid
  end

  it 'is invalid with a duplicate name (case-insensitive) within the same account' do
    create(:role, account:, name: 'Buyer')
    role = build(:role, account:, name: 'buyer')

    expect(role).not_to be_valid
  end

  it 'allows the same name in a different account' do
    create(:role, account:, name: 'Buyer')
    other_account = create(:account)
    role = build(:role, account: other_account, name: 'Buyer')

    expect(role).to be_valid
  end

  it 'prevents destroying a role still referenced by a transaction party',
     skip: 'enabled in Task 6 once TransactionParty exists' do
    role = create(:role, account:)
    create(:transaction_party, role:)

    expect { role.destroy! }.to raise_error(ActiveRecord::DeleteRestrictionError)
  end
end
