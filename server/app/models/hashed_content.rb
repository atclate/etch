class HashedContent < ActiveRecord::Base
  attr_accessible :content, :sha2, :type
  belongs_to :content_owner, :polymorphic => true
end
