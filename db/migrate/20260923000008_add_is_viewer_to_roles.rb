# frozen_string_literal: true

class AddIsViewerToRoles < ActiveRecord::Migration[8.0]
  def change
    add_column :roles, :is_viewer, :boolean, null: false, default: false
  end
end
