# frozen_string_literal: true

RSpec.describe Transaction do
  let(:account) { create(:account) }

  it 'is valid with a name' do
    transaction = build(:transaction, account:, name: '123 E Main St Unit A')

    expect(transaction).to be_valid
  end

  it 'is invalid without a name' do
    transaction = build(:transaction, account:, name: '')

    expect(transaction).not_to be_valid
  end

  it 'defaults to active status' do
    transaction = create(:transaction, account:)

    expect(transaction).to be_active
  end
end
