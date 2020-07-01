# frozen_string_literal: true

module Decidim
  module Ideas
    # A form object to be used when public users want to create an idea.
    class IdeaForm < Decidim::Form
      mimic :idea

      attribute :user_group_id, Integer
      attribute :title, String
      attribute :body, String
      attribute :terms_agreed, Boolean
      attribute :address, String
      attribute :latitude, Float
      attribute :longitude, Float
      attribute :category_id, Integer
      attribute :area_scope_id, Integer
      attribute :image, Decidim::Ideas::ImageAttachmentForm
      attribute :attachment, Decidim::Ideas::AttachmentForm
      attribute :suggested_hashtags, Array[String]

      validates :terms_agreed, presence: true
      validates :title, presence: true, idea_length: {
        minimum: 15,
        maximum: ->(record) { record.component.settings.idea_title_length }
      }
      validates :body, presence: true, idea_length: {
        minimum: 15,
        maximum: ->(record) { record.component.settings.idea_length }
      }
      validates :address, geocoding: true, if: ->(form) { Decidim.geocoder.present? && form.needs_geocoding? }
      validates :category_id, presence: true
      validates :category, presence: true, if: ->(form) { form.category_id.present? }
      validates :area_scope_id, presence: true
      validates :area_scope, presence: true, if: ->(form) { form.area_scope_id.present? }

      validate :idea_length
      validate :area_scope_belongs_to_parent_scope
      validate :notify_missing_attachment_if_errored

      delegate :categories, to: :current_component

      alias component current_component

      def map_model(model)
        @suggested_hashtags = Decidim::ContentRenderers::HashtagRenderer.new(model.body).extra_hashtags.map(&:name).map(&:downcase)

        self.terms_agreed = true unless model.new_record?

        self.user_group_id = model.user_groups.first&.id
        return unless model.categorization

        self.category_id = model.categorization.decidim_category_id
      end

      # Finds the Category from the category_id.
      #
      # Returns a Decidim::Category
      def category
        @category ||= categories.find_by(id: category_id)
      end

      # Finds the Scope from the given decidim_scope_id.
      #
      # Returns a Decidim::Scope
      def area_scope
        @area_scope ||= current_organization.scopes.find_by(id: @area_scope_id)
      end

      # Area Scope identifier
      #
      # Returns the area scope identifier related to the idea
      def area_scope_id
        @area_scope_id || area_scope&.id
      end

      def needs_geocoding?
        return false unless has_address?
        return false if latitude.present? && longitude.present?
        return false if address.blank?

        true
      end

      def has_address?
        current_component.settings.geocoding_enabled?
      end

      def extra_hashtags
        @extra_hashtags ||= (component_automatic_hashtags + suggested_hashtags).uniq
      end

      def suggested_hashtags
        downcased_suggested_hashtags = Array(@suggested_hashtags&.map(&:downcase)).to_set
        component_suggested_hashtags.select { |hashtag| downcased_suggested_hashtags.member?(hashtag.downcase) }
      end

      def suggested_hashtag_checked?(hashtag)
        suggested_hashtags.member?(hashtag)
      end

      def component_automatic_hashtags
        @component_automatic_hashtags ||= ordered_hashtag_list(current_component.current_settings.automatic_hashtags)
      end

      def component_suggested_hashtags
        @component_suggested_hashtags ||= ordered_hashtag_list(current_component.current_settings.suggested_hashtags)
      end

      private

      def idea_length
        return unless body.presence

        length = current_component.settings.idea_length
        errors.add(:body, :too_long, count: length) if body.length > length
      end

      def area_scope_belongs_to_parent_scope
        return unless area_parent_scope

        errors.add(:area_scope_id, :invalid) if !area_parent_scope.ancestor_of?(area_scope)
      end

      def area_parent_scope
        @area_parent_scope ||= begin
          parent_scope_id = current_component.settings.area_scope_parent_id
          return if parent_scope_id.blank?

          current_organization.scopes.find_by(id: parent_scope_id)
        end
      end

      # This method will add an error to the `attachment` field only if there's
      # any error in any other field. This is needed because when the form has
      # an error, the attachment is lost, so we need a way to inform the user of
      # this problem.
      def notify_missing_attachment_if_errored
        errors.add(:image, :needs_to_be_reattached) if errors.any? && image.present?
        errors.add(:attachment, :needs_to_be_reattached) if errors.any? && attachment.present?
      end

      def ordered_hashtag_list(string)
        string.to_s.split.reject(&:blank?).uniq.sort_by(&:parameterize)
      end
    end
  end
end
