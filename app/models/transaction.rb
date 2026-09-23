# frozen_string_literal: true

class Transaction < ApplicationRecord
  belongs_to :account
  belongs_to :created_by_user, class_name: 'User', optional: true

  has_many :transaction_parties, dependent: :destroy
  has_many :envelopes, dependent: :destroy

  enum :status, { active: 0, closed: 1 }

  validates :name, presence: true
end
