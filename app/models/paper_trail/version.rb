module PaperTrail
  class Version < ActiveRecord::Base
    include PaperTrail::VersionConcern

    def actor
      @_actor ||= User.find_by(id: whodunnit) if whodunnit.present?
    end
  end
end
