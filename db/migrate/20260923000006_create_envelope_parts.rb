# frozen_string_literal: true

class CreateEnvelopeParts < ActiveRecord::Migration[8.0]
  def change
    create_table :envelope_parts do |t|
      t.references :envelope, null: false, foreign_key: true, index: true
      t.references :transaction_party, null: false, foreign_key: true, index: true

      t.timestamps
    end
  end
end
