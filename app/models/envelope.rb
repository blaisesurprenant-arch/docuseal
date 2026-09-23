# frozen_string_literal: true

class Envelope < ApplicationRecord
  # :transaction is a reserved association name (Rails 8 raises: it would
  # shadow ActiveRecord::Base#transaction, the DB-transaction helper every
  # model inherits) — named :parent_transaction instead; FK column stays
  # transaction_id.
  belongs_to :parent_transaction, class_name: 'Transaction', foreign_key: :transaction_id,
                                  inverse_of: :envelopes
  belongs_to :template, optional: true
  belongs_to :submission, optional: true

  has_many :envelope_source_templates, -> { order(:position) }, inverse_of: :envelope, dependent: :destroy
  has_many :source_templates, through: :envelope_source_templates
  has_many :envelope_parts, dependent: :destroy
  has_many :transaction_parties, through: :envelope_parts

  enum :status, { draft: 0, sent: 1, completed: 2, voided: 3 }

  validates :name, presence: true
end
