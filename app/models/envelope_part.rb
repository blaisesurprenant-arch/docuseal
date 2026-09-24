# frozen_string_literal: true

class EnvelopePart < ApplicationRecord
  belongs_to :envelope
  belongs_to :transaction_party
  belongs_to :submitter, optional: true
end
