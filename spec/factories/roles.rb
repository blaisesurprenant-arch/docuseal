# frozen_string_literal: true

FactoryBot.define do
  factory :role do
    account

    sequence(:name) { |n| "Role #{n}" }
  end
end
