# frozen_string_literal: true

FactoryBot.define do
  factory :transaction do
    account

    sequence(:name) { |n| "123 Test St Unit #{n}" }
  end
end
