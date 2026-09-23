# frozen_string_literal: true

class Role < ApplicationRecord
  belongs_to :account

  has_many :transaction_parties, dependent: :restrict_with_exception

  validates :name, presence: true
  validates :name, uniqueness: { scope: :account_id, case_sensitive: false }
end
