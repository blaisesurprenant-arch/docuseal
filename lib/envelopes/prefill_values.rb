# frozen_string_literal: true

module Envelopes
  module PrefillValues
    module_function

    def call(party:, field_names:)
      candidates = {
        'Name' => party.signer_name,
        'Email' => party.email,
        'Phone' => party.phone,
        'Address' => format_address(party),
        'Company' => (party.company_name if party.business?),
        'Title' => (party.signer_title if party.business?)
      }

      candidates.slice(*field_names).compact_blank
    end

    def format_address(party)
      return nil if party.address_street.blank?

      [party.address_street, party.address_city, [party.address_state, party.address_zip].compact_blank.join(' ')]
        .compact_blank.join(', ')
    end
  end
end
