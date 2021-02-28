# ## Schema Information
#
# Table name: `bundle_definition_game_entries`
#
# ### Columns
#
# Name                        | Type               | Attributes
# --------------------------- | ------------------ | ---------------------------
# **`id`**                    | `bigint`           | `not null, primary key`
# **`price_currency`**        | `string`           | `default("GBP")`
# **`price_decimals`**        | `integer`          | `default(0)`
# **`created_at`**            | `datetime`         | `not null`
# **`updated_at`**            | `datetime`         | `not null`
# **`bundle_definition_id`**  | `bigint`           | `not null`
# **`game_id`**               | `bigint`           | `not null`
#
class BundleDefinitionGameEntry < ApplicationRecord
  belongs_to :bundle_definition
  belongs_to :game

  monetize :price_decimals, allow_nil: true

  after_commit :update_assignments, on: [:update]

private

  def update_assignments
    bundle_definition.update_assignments
  end
end