# frozen_string_literal: true

class Role < ApplicationRecord
  belongs_to :account

  validates :name, presence: true
  validates :name, uniqueness: { scope: :account_id, case_sensitive: false }
end
