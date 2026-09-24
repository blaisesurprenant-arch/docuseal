# frozen_string_literal: true

class EnvelopeSendController < ApplicationController
  load_and_authorize_resource :transaction
  load_and_authorize_resource :envelope, through: :transaction

  def show
    merged_template = ensure_merged_template
    @prefillable_fields = merged_template.fields.select { |f| f['prefillable'] }
    load_candidate_parties
  end

  def create
    party_ids = Array(params[:party_ids]).compact_blank

    if party_ids.blank?
      flash.now[:alert] = 'Select at least one party.'
      @prefillable_fields = merged_template_for_render.fields.select { |f| f['prefillable'] }
      load_candidate_parties
      return render :show, status: :unprocessable_content
    end

    parties = TransactionParty.where(id: party_ids)
    merged_template = ensure_merged_template
    signing_order = params.dig(:envelope, :signing_order)
    @envelope.signing_order = signing_order if Envelope.signing_orders.key?(signing_order)

    ActiveRecord::Base.transaction do
      @envelope.save!
      parties.each { |party| @envelope.envelope_parts.create!(transaction_party: party) }

      submission = Submission.create!(
        account: current_account,
        template: merged_template,
        created_by_user: current_user,
        submitters_order: @envelope.signing_order_parallel? ? 'random' : 'preserved',
        template_submitters: merged_template.submitters,
        template_fields: merged_template.fields,
        template_schema: merged_template.schema,
        expire_at: params.dig(:envelope, :expire_at).presence
      )

      build_submitters(submission, merged_template, parties)

      @envelope.update!(submission:, status: :sent)
    end

    redirect_to transaction_envelope_path(@transaction, @envelope), notice: 'Envelope has been sent.'
  end

  private

  # Merges lazily on first visit so the resulting Template is a real, saved
  # record the user can jump into the standalone template editor and adjust
  # (field placement, etc.) before actually sending. Reused on later visits
  # and at send time rather than re-merged, so edits made in the template
  # editor survive. EnvelopesController#update clears envelope.template
  # when the source document set changes, which is what makes this
  # re-merge on the next visit.
  def ensure_merged_template
    return @envelope.template if @envelope.template.present?

    merged_template = Envelopes::Merge.call(envelope: @envelope, author: current_user)
    @envelope.update!(template: merged_template)
    merged_template
  end

  def build_submitters(submission, merged_template, parties)
    manual_values = params.dig(:envelope, :prefill_values)&.to_unsafe_h || {}

    merged_template.submitters.each do |template_submitter|
      party = parties.detect { |p| p.role.name == template_submitter['name'] }

      next unless party

      fields_for_submitter = merged_template.fields.select { |f| f['submitter_uuid'] == template_submitter['uuid'] }
      field_names = fields_for_submitter.filter_map { |f| f['name'] }

      # Submitter#values is keyed by field uuid everywhere it's read
      # (lib/submitters/submit_values.rb, generate_audit_trail.rb, etc.) --
      # PrefillValues itself returns a name-keyed hash (its own unit contract),
      # so it has to be remapped to uuids here, at the one place that knows
      # both the field list and the submitter it belongs to.
      name_values = Envelopes::PrefillValues.call(party:, field_names:)
      values = fields_for_submitter.each_with_object({}) do |field, acc|
        manual_value = manual_values[field['uuid']]

        if field['prefillable'] && manual_value.present?
          acc[field['uuid']] = manual_value
        elsif (value = name_values[field['name']]).present?
          acc[field['uuid']] = value
        end
      end

      submitter = submission.submitters.create!(
        account: current_account,
        uuid: template_submitter['uuid'],
        email: party.email,
        name: party.signer_name,
        values:
      )

      @envelope.envelope_parts.find_by(transaction_party: party)&.update!(submitter:)
    end
  end

  def merged_template_for_render
    @envelope.template || Envelopes::Merge.call(envelope: @envelope, author: current_user)
  end

  def load_candidate_parties
    @role_names = @envelope.source_templates.flat_map { |t| t.submitters.pluck('name') }.uniq
    @candidate_parties = @transaction.transaction_parties.includes(:role)
                                     .select { |p| @role_names.include?(p.role.name) }
  end
end
