class Predict < ActiveRecord::Base
  attr_accessible :file, :name, :result
  belongs_to :client
  has_many :hashed_contents, :as => :content_owner, :dependent => :destroy
end
