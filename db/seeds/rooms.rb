# Create ED Rooms (E01-E20)
puts "Creating ED rooms..."
(1..20).each do |i|
  Room.find_or_create_by!(number: "E#{i.to_s.rjust(2, '0')}") do |room|
    room.room_type = :ed
    room.status = :available
  end
end

# Create RP Rooms (R01-R12)
puts "Creating RP rooms..."
(1..12).each do |i|
  Room.find_or_create_by!(number: "R#{i.to_s.rjust(2, '0')}") do |room|
    room.room_type = :rp
    room.status = :available
  end
end

puts "Created #{Room.ed_rooms.count} ED rooms and #{Room.rp_rooms.count} RP rooms"