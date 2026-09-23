# frozen_string_literal: true

class CreateEnvelopeSourceTemplates < ActiveRecord::Migration[8.0]
  def change
    create_table :envelope_source_templates do |t|
      t.references :envelope, null: false, foreign_key: true, index: true
      t.references :source_template, null: false, foreign_key: { to_table: :templates }, index: true
      t.integer :position, null: false, default: 0

      t.timestamps
    end
  end
end
