# frozen_string_literal: true

class AddVoidReasonToEnvelopes < ActiveRecord::Migration[8.0]
  def change
    add_column :envelopes, :void_reason, :text
  end
end
