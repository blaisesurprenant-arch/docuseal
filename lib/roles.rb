# frozen_string_literal: true

module Roles
  module_function

  def find_or_create_by_name(account, name)
    return nil if name.blank?

    normalized_name = name.to_s.strip

    account.roles.where('lower(name) = ?', normalized_name.downcase).first ||
      account.roles.create!(name: normalized_name)
  end
end
