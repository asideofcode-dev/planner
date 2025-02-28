class Event < ActiveRecord::Base
  include Listable
  include Invitable
  include DateTimeConcerns
  include EventHelper

  attr_accessor :begins_at

  resourcify :permissions, role_cname: 'Permission', role_table_name: :permission

  belongs_to :venue, class_name: 'Sponsor'
  has_many :sponsorships
  has_many :sponsors, -> { where('sponsorships.level' => nil) }, through: :sponsorships, source: :sponsor
  has_many :bronze_sponsors, -> { where('sponsorships.level' => 'bronze') }, through: :sponsorships, source: :sponsor
  has_many :silver_sponsors, -> { where('sponsorships.level' => 'silver') }, through: :sponsorships, source: :sponsor
  has_many :gold_sponsors, -> { where('sponsorships.level' => 'gold') }, through: :sponsorships, source: :sponsor
  has_many :organisers, -> { where('permissions.name' => 'organiser') }, through: :permissions, source: :members
  has_and_belongs_to_many :chapters
  has_many :invitations

  validates :name, :slug, :info, :schedule, :description, presence: true
  validates :slug, uniqueness: true
  validate :invitability, if: :invitable?
  validates :coach_spaces, :student_spaces, numericality: true
  validate :sponsors_uniqueness
  validate :bronze_sponsors_uniqueness
  validate :silver_sponsors_uniqueness
  validate :gold_sponsors_uniqueness
  validate :venue_or_remote_must_be_present

  before_save do
    begins_at = Time.parse(self.begins_at)
    self.date_and_time = date_and_time.change(hour: begins_at.hour, min: begins_at.min)
  end

  def to_s
    name
  end

  def to_param
    slug
  end

  def verified_coaches
    invitations.coaches.accepted.verified.map(&:member)
  end

  def verified_students
    invitations.students.accepted.verified.map(&:member)
  end

  def coaches_only?
    student_spaces.zero?
  end

  def students_only?
    coach_spaces.zero?
  end

  def coach_spaces?
    !students_only? && coach_spaces > attending_coaches.count
  end

  def student_spaces?
    !coaches_only? && student_spaces > attending_students.count
  end

  def date
    I18n.l(date_and_time, format: :dashboard)
  end

  def invitability
    errors.add(:coach_spaces, :required) if coach_spaces.blank?
    errors.add(:student_spaces, :required) if student_spaces.blank?
    errors.add(:invitable, :all_invitation_details_required) \
      if coach_spaces.blank? || student_spaces.blank?
  end

  def student_emails
    invitations.students.where(attending: true).map { |i| i.member.email }
  end

  def coach_emails
    invitations.coaches.where(attending: true).map { |i| i.member.email }
  end

  def permitted_audience_values
    %w[Students Coaches]
  end

  def sponsors?(level = nil)
    case level
    when :gold then gold_sponsors.any?
    when :silver then silver_sponsors.any?
    when :bronze then bronze_sponsors.any?
    when :standard then sponsors.any?
    else sponsorships.any?
    end
  end

  private

  def time_zone
    'London'
  end

  def duplicated_sponsors
    @duplicated_sponsors ||= fetch_duplicated_sponsors
  end

  def fetch_duplicated_sponsors
    ids = sponsorships.reject(&:marked_for_destruction?).map(&:sponsor_id)
    ids.select { |e| ids.count(e) > 1 }
  end
end
