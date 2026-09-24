# frozen_string_literal: true

class TransactionParty < ApplicationRecord
  belongs_to :parent_transaction, class_name: 'Transaction', foreign_key: :transaction_id,
                                  inverse_of: :transaction_parties
  belongs_to :role

  has_many :envelope_parts, dependent: :destroy
  has_many :envelopes, through: :envelope_parts

  enum :party_type, { individual: 0, business: 1 }

  validates :first_name, :last_name, presence: true, if: :individual?
  validates :company_name, :signer_first_name, :signer_last_name, :signer_title, presence: true, if: :business?
  validates :email, presence: true

  def display_name
    if business?
      "#{company_name} (#{signer_first_name} #{signer_last_name})"
    else
      "#{first_name} #{last_name}"
    end
  end

  def signer_name
    business? ? "#{signer_first_name} #{signer_last_name}" : "#{first_name} #{last_name}"
  end
end
