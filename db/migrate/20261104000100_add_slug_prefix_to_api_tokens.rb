class AddSlugPrefixToApiTokens < ActiveRecord::Migration[8.0]
  def change
    add_column :api_tokens, :slug_prefix, :string
  end
end
