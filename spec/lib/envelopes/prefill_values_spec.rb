# frozen_string_literal: true

RSpec.describe Envelopes::PrefillValues do
  let(:account) { create(:account) }
  let(:transaction) { create(:transaction, account:) }
  let(:role) { create(:role, account:, name: 'Buyer') }

  it 'maps an individual party contact info to matching field names' do
    party = create(:transaction_party, parent_transaction: transaction, role:, first_name: 'Jane', last_name: 'Doe',
                                       email: 'jane@example.com', phone: '555-1234',
                                       address_street: '1 Main St', address_city: 'Springfield',
                                       address_state: 'IL', address_zip: '62704')

    values = Envelopes::PrefillValues.call(party:, field_names: %w[Name Email Phone Address Company Title])

    expect(values).to eq(
      'Name' => 'Jane Doe',
      'Email' => 'jane@example.com',
      'Phone' => '555-1234',
      'Address' => '1 Main St, Springfield, IL 62704'
    )
  end

  it 'maps a business party contact info, including company and signer title' do
    party = create(:transaction_party, :business, parent_transaction: transaction, role:, email: 'jane@acme.com')

    values = Envelopes::PrefillValues.call(party:, field_names: %w[Name Email Company Title])

    expect(values).to eq(
      'Name' => 'Jane Doe',
      'Email' => 'jane@acme.com',
      'Company' => 'Acme LLC',
      'Title' => 'Managing Member'
    )
  end

  it 'omits fields the template does not define' do
    party = create(:transaction_party, parent_transaction: transaction, role:, first_name: 'Jane', last_name: 'Doe')

    values = Envelopes::PrefillValues.call(party:, field_names: %w[Name])

    expect(values).to eq('Name' => 'Jane Doe')
  end
end
