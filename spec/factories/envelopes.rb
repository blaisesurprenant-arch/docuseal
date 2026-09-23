# frozen_string_literal: true

FactoryBot.define do
  factory :envelope do
    parent_transaction { association :transaction }

    sequence(:name) { |n| "Envelope #{n}" }
  end
end
