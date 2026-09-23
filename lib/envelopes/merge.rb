# frozen_string_literal: true

module Envelopes
  module Merge
    module_function

    def call(envelope:, author:)
      merged = author.account.templates.new(
        name: envelope.name,
        author:,
        folder: author.account.default_template_folder,
        submitters: [],
        fields: [],
        schema: [],
        preferences: {}
      )

      role_uuid_by_name = {}
      source_attachment_uuids_by_template_id = {}

      envelope.source_templates.each do |source_template|
        merge_source_template(merged, source_template, role_uuid_by_name)

        source_attachment_uuids_by_template_id[source_template.id] =
          source_template.schema.pluck('attachment_uuid')
      end

      merged.save!

      attach_documents(merged, envelope.source_templates, source_attachment_uuids_by_template_id)

      envelope.template = merged

      merged
    end

    def merge_source_template(merged, source_template, role_uuid_by_name)
      cloned_submitters, cloned_fields, cloned_schema, =
        Templates::Clone.update_submitters_and_fields_and_schema(
          source_template.submitters.deep_dup,
          source_template.fields.deep_dup,
          source_template.schema.deep_dup,
          source_template.preferences.deep_dup
        )

      uuid_remap = {}

      cloned_submitters.each do |submitter|
        canonical_uuid = role_uuid_by_name[submitter['name']]

        if canonical_uuid
          uuid_remap[submitter['uuid']] = canonical_uuid
        else
          role_uuid_by_name[submitter['name']] = submitter['uuid']
          merged.submitters << submitter
        end
      end

      cloned_fields.each do |field|
        remapped = uuid_remap[field['submitter_uuid']]
        field['submitter_uuid'] = remapped if remapped
      end

      merged.fields.concat(cloned_fields)
      merged.schema.concat(cloned_schema)
    end

    def attach_documents(merged, source_templates, source_attachment_uuids_by_template_id)
      source_templates.each do |source_template|
        this_source_uuids = source_attachment_uuids_by_template_id.fetch(source_template.id)
        excluded_attachment_uuids = merged.schema.pluck('attachment_uuid') - this_source_uuids

        Templates::CloneAttachments.call(
          template: merged,
          original_template: source_template,
          excluded_attachment_uuids:
        )
      end
    end
  end
end
