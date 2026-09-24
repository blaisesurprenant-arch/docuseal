# frozen_string_literal: true

class AddSubmitterIdToEnvelopeParts < ActiveRecord::Migration[8.0]
  def change
    add_reference :envelope_parts, :submitter, null: true, foreign_key: true, index: true
  end
end
