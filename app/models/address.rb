class Address < ApplicationRecord
  belongs_to :addressable, polymorphic: true

  attribute :country_code, default: "JP"

  validates :country_code, presence: true
  validates :postal_code, presence: true
  validate :country_code_must_be_valid
  validate :validate_jp_fields, if: :jp?
  validate :validate_es_fields, if: :es?
  validates :street, presence: true, unless: :jp?

  JP_POSTAL_CODE_FORMAT = /\A\d{3}-?\d{4}\z/
  JP_PREFECTURES = ISO3166::Country["JP"].subdivisions.values.map { it.translations[:ja] }.freeze

  ES_POSTAL_CODE_FORMAT = /\A\d{5}\z/
  ES_PROVINCES = ISO3166::Country["ES"].subdivisions.select { |_, v| v.type == "province" }.values.map(&:name).freeze

  FIELD_PARTIALS = {
    "ES" => "addresses/es_fields",
    "JP" => "addresses/jp_fields"
  }.freeze

  COUNTRY_OPTIONS = ISO3166::Country.all
    .sort_by(&:iso_short_name)
    .map { [ _1.iso_short_name, _1.alpha2 ] }
    .freeze

  def fields_partial
    FIELD_PARTIALS.fetch(country_code, "addresses/generic_fields")
  end

  def es? = country_code == "ES"
  def jp? = country_code == "JP"

  def formatted_lines
    if jp?
      jp_formatted_lines
    elsif es?
      es_formatted_lines
    else
      generic_formatted_lines
    end.compact_blank
  end

  private

  def country_code_must_be_valid
    return if country_code.blank?
    errors.add :country_code, :invalid unless ISO3166::Country[country_code]
  end

  def validate_es_fields
    if postal_code.present? && !postal_code.match?(ES_POSTAL_CODE_FORMAT)
      errors.add :postal_code, :invalid
    end
    if administrative_area.present? && !ES_PROVINCES.include?(administrative_area)
      errors.add :administrative_area, :invalid
    end
    errors.add :locality, :blank if locality.blank?
    errors.add :street, :blank if street.blank?
    errors.add :administrative_area, :blank if administrative_area.blank?
  end

  def validate_jp_fields
    if postal_code.present? && !postal_code.match?(JP_POSTAL_CODE_FORMAT)
      errors.add :postal_code, :invalid
    end
    if administrative_area.present? && !JP_PREFECTURES.include?(administrative_area)
      errors.add :administrative_area, :invalid
    end
    errors.add :locality, :blank if locality.blank?
    errors.add :administrative_area, :blank if administrative_area.blank?
  end

  def es_formatted_lines
    [
      street,
      extended,
      [ postal_code, locality ].compact_blank.join(" "),
      administrative_area,
      "España"
    ]
  end

  def generic_formatted_lines
    [
      street,
      extended,
      [ locality, administrative_area, postal_code ].compact_blank.join(" "),
      ISO3166::Country[country_code]&.iso_short_name
    ]
  end

  def jp_formatted_lines
    [
      "〒#{postal_code}",
      [ administrative_area, locality, sublocality ].compact_blank.join(" "),
      street,
      extended
    ]
  end
end
