# frozen_string_literal: true

FactoryBot.define do
  factory :transaction_party do
    parent_transaction { association :transaction }
    role

    party_type { 'individual' }
    first_name { 'Jane' }
    last_name { 'Doe' }
    email { 'jane@example.com' }

    trait :business do
      party_type { 'business' }
      company_name { 'Acme LLC' }
      signer_first_name { 'Jane' }
      signer_last_name { 'Doe' }
      signer_title { 'Managing Member' }
    end
  end
end
