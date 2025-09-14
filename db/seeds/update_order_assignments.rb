# Update existing orders with nurse assignments
CarePathwayOrder.find_each do |order|
  # Assign based on order type
  assignment = case order.order_type.to_sym
               when :medication
                 'ED RN'  # Medications go to ED RN
               when :lab
                 'RP RN'  # Labs go to RP RN
               when :imaging
                 'ED RN'  # Imaging goes to ED RN
               else
                 nil
               end

  order.update_column(:assigned_to, assignment) if assignment
end

puts "Updated #{CarePathwayOrder.where.not(assigned_to: nil).count} orders with nurse assignments"