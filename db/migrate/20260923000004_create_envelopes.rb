# frozen_string_literal: true

class CreateEnvelopes < ActiveRecord::Migration[8.0]
  def change
    create_table :envelopes do |t|
      t.references :transaction, null: false, foreign_key: true, index: true
      t.references :template, null: true, foreign_key: true, index: true
      t.references :submission, null: true, foreign_key: true, index: true

      t.string :name, null: false
      t.integer :status, null: false, default: 0

      t.timestamps
    end
  end
end
