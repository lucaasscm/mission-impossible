User.find_or_create_by!(email_address: "admin@videira.local") { |u| u.password = "password" }
