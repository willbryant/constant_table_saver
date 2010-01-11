ActiveRecord::Schema.define(:version => 0) do
  create_table :pies, :force => true do |t|
    t.string   :filling, :null => false
  end
  
  create_table :ingredients, :force => true do |t|
    t.integer  :pie_id, :null => false
    t.string   :name,   :null => false
  end
end
