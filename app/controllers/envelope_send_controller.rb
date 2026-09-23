# frozen_string_literal: true

class EnvelopeSendController < ApplicationController
  load_and_authorize_resource :transaction
  load_and_authorize_resource :envelope, through: :transaction

  def show
    load_candidate_parties
  end

  def create
    party_ids = Array(params[:party_ids]).compact_blank

    if party_ids.blank?
      flash.now[:alert] = 'Select at least one party.'
      load_candidate_parties
      return render :show, status: :unprocessable_content
    end

    parties = TransactionParty.where(id: party_ids)

    ActiveRecord::Base.transaction do
      parties.each { |party| @envelope.envelope_parts.create!(transaction_party: party) }

      merged_template = Envelopes::Merge.call(envelope: @envelope, author: current_user)

      submission = Submission.create!(
        account: current_account,
        template: merged_template,
        created_by_user: current_user,
        submitters_order: 'preserved'
      )

      build_submitters(submission, merged_template, parties)

      @envelope.update!(template: merged_template, submission:, status: :sent)
    end

    redirect_to transaction_envelope_path(@transaction, @envelope), notice: 'Envelope has been sent.'
  end

  private

  def build_submitters(submission, merged_template, parties)
    merged_template.submitters.each do |template_submitter|
      party = parties.detect { |p| p.role.name == template_submitter['name'] }

      next unless party

      field_names = merged_template.fields.select { |f| f['submitter_uuid'] == template_submitter['uuid'] }
                                   .filter_map { |f| f['name'] }

      submission.submitters.create!(
        account: current_account,
        uuid: template_submitter['uuid'],
        email: party.email,
        name: party.signer_name,
        values: Envelopes::PrefillValues.call(party:, field_names:)
      )
    end
  end

  def load_candidate_parties
    @role_names = @envelope.source_templates.flat_map { |t| t.submitters.pluck('name') }.uniq
    @candidate_parties = @transaction.transaction_parties.includes(:role)
                                     .select { |p| @role_names.include?(p.role.name) }
  end
end
