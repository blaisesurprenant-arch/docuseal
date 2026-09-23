# frozen_string_literal: true

RSpec.describe TransactionParty do
  let(:account) { create(:account) }
  let(:transaction) { create(:transaction, account:) }
  let(:role) { create(:role, account:) }

  it 'is valid as an individual with a name and email' do
    party = build(:transaction_party, transaction:, role:, party_type: 'individual',
                                      first_name: 'Jane', last_name: 'Doe', email: 'jane@example.com')

    expect(party).to be_valid
  end

  it 'requires first and last name for an individual' do
    party = build(:transaction_party, transaction:, role:, party_type: 'individual', first_name: '', last_name: '')

    expect(party).not_to be_valid
    expect(party.errors[:first_name]).to be_present
    expect(party.errors[:last_name]).to be_present
  end

  it 'is valid as a business with a company name and a signer name/title' do
    party = build(:transaction_party, transaction:, role:, party_type: 'business',
                                      company_name: 'Acme LLC', signer_first_name: 'Jane',
                                      signer_last_name: 'Doe', signer_title: 'Managing Member',
                                      email: 'jane@acme.com')

    expect(party).to be_valid
  end

  it 'requires company name, signer name, and signer title for a business' do
    party = build(:transaction_party, transaction:, role:, party_type: 'business',
                                      company_name: '', signer_first_name: '', signer_last_name: '',
                                      signer_title: '')

    expect(party).not_to be_valid
    expect(party.errors[:company_name]).to be_present
    expect(party.errors[:signer_first_name]).to be_present
    expect(party.errors[:signer_last_name]).to be_present
    expect(party.errors[:signer_title]).to be_present
  end

  it 'builds a display name for an individual' do
    party = build(:transaction_party, transaction:, role:, party_type: 'individual',
                                      first_name: 'Jane', last_name: 'Doe')

    expect(party.display_name).to eq('Jane Doe')
  end

  it 'builds a display name for a business' do
    party = build(:transaction_party, transaction:, role:, party_type: 'business',
                                      company_name: 'Acme LLC', signer_first_name: 'Jane', signer_last_name: 'Doe')

    expect(party.display_name).to eq('Acme LLC (Jane Doe)')
  end
end
